# drama3-local-streaming

Running the [Fish Audio Drama 3](https://www.marktechpost.com/2026/10/14/fish-audio-drama-3-open-weight-tts-model/) speech model locally on a consumer PC with an 8 GB GPU, by keeping what fits in VRAM and RAM and streaming the rest of the model's experts from an NVMe SSD.

The target use is offline narration: script in, audio file out. The project has turned into local-model optimisation in its own right: loaders, SSD streaming, expert offload and quantisation on one PC, with Drama 3 as the test subject.

## Where it stands

**Best setup so far: native Windows Vulkan build of speech.cpp with our patches, mmap loader with prefetch, Q2_K routed experts. 0.70× realtime, ready in 11 s, 7.4 GB of RAM** (stock under WSL: 0.44×, 287 s to start, 16 GB). Full numbers in [RESULTS.md](RESULTS.md).

- **mmap loader**: startup in seconds instead of minutes, bit-identical output, and the model runs under a 16 GB RAM cap where the stock loader is OOM-killed.
- **SSD streaming works**, and prefetching the router's chosen experts makes it 1.5–2.25× faster under a RAM cap.
- **The speed limit is the GPU↔CPU handoff** (about 1.1 ms per CPU-computed layer per frame), so what helps is fitting more layers on the GPU (smaller expert quants) and a cheaper handoff (native Windows rather than WSL).
- **Q2_K experts** give 1.4× the speed at 55% of the RAM for about +0.6 WER points, and came out on top in a blind listening test.

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
| [`narrate.cmd`](narrate.cmd), [`narrate.py`](narrate.py) | Narrate a text file on the best setup: one segment per line, several takes each, a stitched `narration.wav`. Example input: [`examples-cold-open.txt`](examples-cold-open.txt). |
| [`scorecard/`](scorecard/) | The test harness, a library of three stages: `gen.py` (one loaded `speech worker`, every take) → `asr.py` (Qwen3-ASR) → `score.py` (WER/CER, flags). Also `mos.py` (UTMOS, voice drift), `kana_cer.py` (Japanese kana CER), `expert_stats.py` (router logs, cache simulation), `fidelity.py` (teacher-forced KL). Unit tests are `test_*.py`. |
| `scorecard/*.sh` | Experiment drivers: `exp_queue.sh` (threads, load, experts), `mmap_sweep.sh` / `ra_test.sh` (RAM cap, readahead), `pf_sweep.sh` (expert prefetch), `tier_runs.sh` / `ovh*_runs.sh` (hot-expert tiering, handoff overhead), `quant_fid.sh` / `quant_score.sh` (quants, KL), `bench.sh ja\|en` (public benchmarks). |
| `scorecard/corpus*.jsonl` | Fixed text sets: 20 English sentences + 1 paragraph, a contrast set, speech-bench's Japanese prompts, a 100-utterance LibriSpeech test-clean subset. |
| `scorecard/tools/` | Helpers: speed and step summaries, sweep stats, the listening-pack builder, the Windows build script and benchmark wrappers. |

The scripts carry the paths of the rig they ran on (`/mnt/c/Users/...`, `~/drama3/...`, `~/models/...`); edit them for yours.

This repo holds patches, scripts and measurements only. It does not include the model weights, generated audio or the speech.cpp source; get those from their own projects. [speech.cpp](https://github.com/nyosegawa/speech.cpp) is the runtime; the patches apply to it.

## Plan and progress

1. **Baseline.** Done: 0.4× realtime, 16 GB anonymous RAM, no streaming (speech.cpp reads the whole file with fread), OOM under a 16 GB cap.
2. **Expert usage logging.** Done: routing is broad (90% of experts used), and the hot set is general, not workload-specific.
3. **Tiered cache.** mmap streaming and router-driven prefetch: done and working. Hot experts in VRAM: works but gains only 8% and is unstable, because the per-layer handoff dominates.
4. **Smaller experts and native Windows.** Done: Q2_K experts on native Vulkan is the best setup.
5. **Quality check.** KL fidelity, two public benchmarks and a blind listening test: done for Q4_K, IQ4_XS, Q3_K, IQ3_S and Q2_K experts.
6. **Batch paragraphs.** Not started.

Next: what the listening issues are (prosody, artifacts, pacing) and reference-voice files; an importance matrix for the IQ quants; KL on more sentences; Q2_K with prefetch under an 8 GB cap.

## Licence note

Drama 3 is under the Fish Audio Community License v1.0: free commercial use under US$500k annual revenue, products must show "Built with Fish Audio", no cloning a real voice without consent, and serving it as a third-party API needs a separate licence.
