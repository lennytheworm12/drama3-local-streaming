# drama3-local-streaming

This repository documents our work on running the [Fish Audio Drama 3](https://www.marktechpost.com/2026/10/14/fish-audio-drama-3-open-weight-tts-model/) speech model locally on a consumer PC with an 8 GB GPU. The approach is to keep whatever fits in VRAM and RAM, and to stream the rest of the model's experts from an NVMe SSD.

Our original target was offline narration: a script goes in and an audio file comes out. Over time the project has become a study of local-model optimisation in its own right, covering loaders, SSD streaming, expert offload and quantisation on a single PC, with Drama 3 as the test subject.

## Current state

**Our best setup so far is a native Windows Vulkan build of speech.cpp with our patches and an English-imatrix mixed-precision file (routed experts Q4_K, the rest Q6_K/Q8_0, 21.8 GB). A single take runs at 0.77× realtime, and four takes run side by side reach 1.24–1.27× realtime throughput.** For comparison, the stock build under WSL runs at 0.44×, takes 287 s to start and uses 16 GB. The full numbers are in [RESULTS.md](RESULTS.md).

- **mmap loader.** Startup takes seconds instead of minutes, the output is bit-identical, and the model runs under a 16 GB RAM cap where the stock loader is OOM-killed.
- **SSD streaming works.** On native Windows, a whole-expert LRU cache with overlapped unbuffered reads runs at 0.40× / 0.34× / 0.27× realtime in 12 / 10 / 8 GB of RAM (`narrate.cmd --ram-gb N`), and its takes are identical to the in-RAM run. The overlapped reads were what made the difference (+60–95%); pinning hot experts, a contiguous layout and read-ahead did not help.
- **Hot experts at Q6_K** (`narrate.cmd --hot q6`). Storing the 30% most-routed experts per layer at a higher type halves the main token's KL again (top-token match 93.1%) at a cost of about 13% in speed.
- **The speed limit is the GPU↔CPU handoff and small GPU dispatches.** What helps, therefore, is fitting more layers on the GPU and making the handoff cheaper (native Windows rather than WSL).
- **The fused audio decoder, freed VRAM and flash attention** together took one Q4_K take from 0.65× to 0.77×. The VRAM savings (half-precision caches sized for a line, `token_embd` on the CPU) are also what allowed four concurrent takes to fit.
- **An English importance matrix, with Q6_K outside the experts,** reduces the error against F16 to a fraction of its former value at the same speed and +1 GB. Main-token KL is 0.027 against 0.073 for the published Q4_K (top-token match 86.1% against 75.0%), and codebook KL is 0.019 against 0.156 (match 83.2% against 53.1%). This is now the default model. Four takes peak at 7.4 of 8 GB VRAM, so we recommend `--streams 3` when other GPU apps are open. Our blind listening comparison against the published file is still pending.
- **Pinned host memory for the GPU↔CPU handoffs** adds about 5% (one take 0.71× → 0.75×, four takes 1.16× → 1.22× in same-day runs), with bit-identical audio.
- **Q2_K experts** give 1.4× the speed at 55% of the RAM, for about +0.6 WER points. However, a blind test with a fixed voice found that they flatten intonation, so we keep Q4_K as the quality default.
- **What did not help:** CPU expert repacking, Q8_0, self-draft speculative decoding, one GPU submission per frame, op fusion, next-layer pre-gating, hot-expert tiering, running the shared expert on the GPU beside the CPU experts, and a native CUDA build in place of Vulkan (it was no faster, which tells us the kernels are not the limit).

## Why this is possible

- Drama 3 is a mixture-of-experts model with about 35B parameters: 40 layers, each with 256 routed experts plus 1 shared expert. Each step picks 8 routed experts, so only about 3B parameters are active per step.
- Each step produces one codec frame, at about 21.5 frames per second of audio.
- Because only the active experts are needed at each step, the full model does not have to sit in VRAM, or even in RAM.

## Hardware

- NVIDIA RTX 4060 Ti 8 GB (Ada, SM89)
- Ryzen 7 5700, 32 GB RAM, Windows 11 with WSL2
- Crucial P3 2 TB NVMe SSD (about 1 to 1.8 GB/s measured)

## Repository contents

| Path | What |
|---|---|
| [`RESULTS.md`](RESULTS.md) | The full write-up: baseline, Round 1, quants, native Windows build, prefetch, public benchmarks, listening tests. |
| [`patches/`](patches/) | Our speech.cpp changes as patches against upstream main `eacabcd`, with a description of each switch. |
| [`docs/build-windows.md`](docs/build-windows.md) | How to build the patched speech.cpp natively on Windows with MSVC and Vulkan. |
| [`docs/test-plan.md`](docs/test-plan.md) | The optimisation test plan: experiments, the scorecard, pass/fail criteria. |
| [`docs/step1-baseline.md`](docs/step1-baseline.md) | The first SSD-streaming experiment in full. |
| [`narrate.cmd`](narrate.cmd), [`narrate.py`](narrate.py) | Narrates a text file on the best setup: one segment per line (each under 2,048 prompt rows), several takes per segment generated four at a time (`--streams 1` for one at a time), and a stitched `narration.wav`. Example input: [`examples-cold-open.txt`](examples-cold-open.txt). |
| [`scorecard/`](scorecard/) | The test harness, a library of three stages: `gen.py` (one loaded `speech worker`, every take) → `asr.py` (Qwen3-ASR) → `score.py` (WER/CER, flags). Also `mos.py` (UTMOS, voice drift), `kana_cer.py` (Japanese kana CER), `expert_stats.py` (router logs, cache simulation) and `fidelity.py` (teacher-forced KL). Unit tests are in `test_*.py`. |
| `scorecard/*.sh` | Experiment drivers: `exp_queue.sh` (threads, load, experts), `mmap_sweep.sh` / `ra_test.sh` (RAM cap, readahead), `pf_sweep.sh` (expert prefetch), `tier_runs.sh` / `ovh*_runs.sh` (hot-expert tiering, handoff overhead), `quant_fid.sh` / `quant_score.sh` (quants, KL), `bench.sh ja\|en` (public benchmarks). |
| `scorecard/corpus*.jsonl` | Fixed text sets: 20 English sentences + 1 paragraph, a contrast set, speech-bench's Japanese prompts, and a 100-utterance LibriSpeech test-clean subset. |
| `scorecard/tp.py` | Measures the throughput of a worker serving several takes at once (`SPEECH_STREAMS`). |
| `scorecard/tools/calib.py`, `imx_quant.sh`, `imx2_quant.sh`, `kl_table.py` | Importance-matrix calibration, the imatrix quantisation scripts (round 2 produces the mixed default), and the KL table. `scorecard/fidelity-extra.txt` holds the extra held-out KL sentences. |
| `scorecard/tools/` | Helpers: speed and step summaries, sweep statistics, the listening-pack builders, the Windows build scripts (`build_win3.cmd` is current), the Windows benchmark drivers (`win_bench_*.ps1`) and the Vulkan profile summary (`vk_perf_sum.py`). |

The scripts contain the paths of the machine they ran on (`/mnt/c/Users/...`, `~/drama3/...`, `~/models/...`), so you will need to edit them for your own setup.

This repository holds patches, scripts and measurements only. It does not include the model weights, generated audio or the speech.cpp source; those are available from their own projects. [speech.cpp](https://github.com/nyosegawa/speech.cpp) is the runtime, and the patches apply to it.

## Plan and progress

1. **Baseline.** Done. We measured 0.4× realtime and 16 GB of anonymous RAM, with no streaming (speech.cpp reads the whole file with fread), and an OOM under a 16 GB cap.
2. **Expert usage logging.** Done. Routing is broad (90% of experts are used), and the hot set is general rather than workload-specific.
3. **Tiered cache.** Done. We first built mmap streaming with router prefetch under WSL, then a native Windows expert cache with overlapped SSD reads (`--ram-gb`). Placing hot experts in VRAM works, but it gains only 8% and is unstable, because the per-layer handoff dominates.
4. **Smaller experts and native Windows.** Done. Native Vulkan beats CUDA in WSL, and Q2_K experts are the fast, low-RAM option.
5. **Quality check.** Done: KL fidelity, two public benchmarks and two blind listening tests (the second with a fixed voice file). Q4_K is the quality default.
6. **Q4_K speed.** Done: fused audio decoder, VRAM spill fix, freed VRAM and flash attention, reaching 0.77× for one take.
7. **Batch takes.** Done as concurrent streams: four takes at once give 1.24–1.27× realtime throughput.
8. **Importance matrix.** Done, covering the text model, audio decoder and head, with Q6_K/Q8_0 outside the experts: main KL −63%, codebook KL −88%. The listening test is pending.

Next steps: our blind listening comparison of the imatrix mix against the published Q4_K; batched multi-take decoding (one handoff per layer for every take), which is the main throughput lever left; and imatrix versions of the smaller expert mixes.

## Licence note

Drama 3 is released under the Fish Audio Community License v1.0. It allows free commercial use under US$500k in annual revenue, requires products to show "Built with Fish Audio", forbids cloning a real voice without consent, and requires a separate licence to serve the model as a third-party API.
