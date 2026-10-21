# drama3-local-streaming

Running the [Fish Audio Drama 3](https://www.marktechpost.com/2026/10/14/fish-audio-drama-3-open-weight-tts-model/) speech model locally on a consumer PC with an 8 GB GPU, by keeping what fits in VRAM and RAM and streaming the rest of the model's experts from an NVMe SSD.

The target use is offline narration: script in, audio file out. The project has turned into local-model optimisation in its own right: loaders, SSD streaming, expert offload and quantisation on one PC, with Drama 3 as the test subject.

## Where it stands

**Best setup so far: native Windows Vulkan build of speech.cpp with our patches and an English-imatrix mixed-precision file (routed experts Q4_K, the rest Q6_K/Q8_0, 21.8 GB). One take runs at 0.77× realtime, and four takes side by side give 1.24–1.27× realtime throughput** (stock under WSL: 0.44×, 287 s to start, 16 GB). Full numbers in [RESULTS.md](RESULTS.md).

- **mmap loader**: startup in seconds instead of minutes, bit-identical output, and the model runs under a 16 GB RAM cap where the stock loader is OOM-killed.
- **SSD streaming works.** On native Windows, a whole-expert LRU cache with overlapped unbuffered reads runs at 0.40× / 0.34× / 0.27× realtime in 12 / 10 / 8 GB of RAM (`narrate.cmd --ram-gb N`), with takes identical to the in-RAM run. Overlapped reads were the win (+60–95%); pinning hot experts, a contiguous layout and read-ahead didn't help.
- **Hot experts at Q6_K** (`narrate.cmd --hot q6`): the 30% most-routed experts per layer at a higher type halve the main token's KL again (top-token match 93.1%) for about 13% speed.
- **The speed limit is the GPU↔CPU handoff and small GPU dispatches**, so what helps is fitting more layers on the GPU and a cheaper handoff (native Windows rather than WSL).
- **Fused audio decoder, freed VRAM and flash attention** took one Q4_K take from 0.65× to 0.77×. The VRAM savings (half-precision caches sized for a line, `token_embd` on the CPU) are also what made four concurrent takes fit.
- **An English importance matrix, with Q6_K outside the experts**, cuts the error against F16 to a fraction at the same speed and +1 GB: main-token KL 0.027 against 0.073 for the published Q4_K (top-token match 86.1% against 75.0%), and codebook KL 0.019 against 0.156 (match 83.2% against 53.1%). It's the default model now. Four takes peak at 7.4 of 8 GB VRAM, so use `--streams 3` with other GPU apps open. Bi's blind listen against the published file is pending.
- **Pinned host memory for the GPU↔CPU handoffs** adds about 5% (one take 0.71× → 0.75×, four 1.16× → 1.22× in same-day runs), with bit-identical audio.
- **Q2_K experts** give 1.4× the speed at 55% of the RAM for about +0.6 WER points. A blind test with a fixed voice found they flatten intonation, so Q4_K is the quality default.
- **Didn't help**: CPU expert repacking, Q8_0, self-draft speculative decoding, one GPU submission per frame, op fusion, next-layer pre-gating, hot-expert tiering, the shared expert on the GPU beside the CPU experts, and a native CUDA build in place of Vulkan (no faster, so kernels aren't the limit).

## Why it's possible

- Drama 3 is a mixture-of-experts model: about 35B parameters, 40 layers of 256 routed experts plus 1 shared, 8 picked per step, about 3B active per step.
- Each step produces one codec frame (about 21.5 per second of audio).
- Only the active experts are needed per step, so the full model doesn't have to sit in VRAM or even RAM.

## Target hardware

- NVIDIA RTX 4060 Ti 8 GB (Ada, SM89)
- Ryzen 7 5700, 32 GB RAM, Windows 11 with WSL2
- Crucial P3 2 TB NVMe SSD (about 1 to 1.8 GB/s measured)

## This repo

| Path | What |
|---|---|
| [`RESULTS.md`](RESULTS.md) | The write-up: baseline, Round 1, quants, native Windows build, prefetch, public benchmarks, listening test. |
| [`patches/`](patches/) | Our speech.cpp changes as patches against upstream main `eacabcd`, and what each switch does. |
| [`docs/build-windows.md`](docs/build-windows.md) | Building the patched speech.cpp natively on Windows with MSVC and Vulkan. |
| [`docs/test-plan.md`](docs/test-plan.md) | The optimisation test plan: experiments, the scorecard, pass/fail criteria. |
| [`docs/step1-baseline.md`](docs/step1-baseline.md) | The first SSD-streaming experiment in full. |
| [`narrate.cmd`](narrate.cmd), [`narrate.py`](narrate.py) | Narrate a text file on the best setup: one segment per line (each under 2,048 prompt rows), several takes each generated four at a time (`--streams 1` for one at a time), a stitched `narration.wav`. Example input: [`examples-cold-open.txt`](examples-cold-open.txt). |
| [`scorecard/`](scorecard/) | The test harness, a library of three stages: `gen.py` (one loaded `speech worker`, every take) → `asr.py` (Qwen3-ASR) → `score.py` (WER/CER, flags). Also `mos.py` (UTMOS, voice drift), `kana_cer.py` (Japanese kana CER), `expert_stats.py` (router logs, cache simulation), `fidelity.py` (teacher-forced KL). Unit tests are `test_*.py`. |
| `scorecard/*.sh` | Experiment drivers: `exp_queue.sh` (threads, load, experts), `mmap_sweep.sh` / `ra_test.sh` (RAM cap, readahead), `pf_sweep.sh` (expert prefetch), `tier_runs.sh` / `ovh*_runs.sh` (hot-expert tiering, handoff overhead), `quant_fid.sh` / `quant_score.sh` (quants, KL), `bench.sh ja\|en` (public benchmarks). |
| `scorecard/corpus*.jsonl` | Fixed text sets: 20 English sentences + 1 paragraph, a contrast set, speech-bench's Japanese prompts, a 100-utterance LibriSpeech test-clean subset. |
| `scorecard/tp.py` | Throughput of a worker serving several takes at once (`SPEECH_STREAMS`). |
| `scorecard/tools/calib.py`, `imx_quant.sh`, `imx2_quant.sh`, `kl_table.py` | Importance-matrix calibration, the imatrix quantises (round 2 makes the mixed default), and the KL table. `scorecard/fidelity-extra.txt` holds the extra held-out KL sentences. |
| `scorecard/tools/` | Helpers: speed and step summaries, sweep stats, the listening-pack builders, the Windows build scripts (`build_win3.cmd` is current), the Windows benchmark drivers (`win_bench_*.ps1`) and the Vulkan profile summary (`vk_perf_sum.py`). |

The scripts carry the paths of the rig they ran on (`/mnt/c/Users/...`, `~/drama3/...`, `~/models/...`); edit them for yours.

This repo holds patches, scripts and measurements only. It does not include the model weights, generated audio or the speech.cpp source; get those from their own projects. [speech.cpp](https://github.com/nyosegawa/speech.cpp) is the runtime; the patches apply to it.

## Plan and progress

1. **Baseline.** Done: 0.4× realtime, 16 GB anonymous RAM, no streaming (speech.cpp reads the whole file with fread), OOM under a 16 GB cap.
2. **Expert usage logging.** Done: routing is broad (90% of experts used), and the hot set is general, not workload-specific.
3. **Tiered cache.** Done: mmap streaming with router prefetch under WSL, then a native Windows expert cache with overlapped SSD reads (`--ram-gb`). Hot experts in VRAM: works but gains only 8% and is unstable, because the per-layer handoff dominates.
4. **Smaller experts and native Windows.** Done: native Vulkan beats CUDA in WSL, and Q2_K experts are the fast, low-RAM option.
5. **Quality check.** KL fidelity, two public benchmarks and two blind listening tests (the second with a fixed voice file): done. Q4_K is the quality default.
6. **Q4_K speed.** Done: fused audio decoder, VRAM spill fix, freed VRAM, flash attention. 0.77× for one take.
7. **Batch takes.** Done as concurrent streams: four takes at once give 1.24–1.27× realtime throughput.
8. **Importance matrix.** Done, covering the text model, audio decoder and head, with Q6_K/Q8_0 outside the experts: main KL −63%, codebook KL −88%. Listening test pending.

Next: Bi's blind listen of the imatrix mix against the published Q4_K; batched multi-take decoding (one handoff per layer for every take), the main throughput lever left; imatrix versions of the smaller expert mixes.

## Licence note

Drama 3 is under the Fish Audio Community License v1.0: free commercial use under US$500k annual revenue, products must show "Built with Fish Audio", no cloning a real voice without consent, and serving it as a third-party API needs a separate licence.
