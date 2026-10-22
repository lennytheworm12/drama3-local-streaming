# Drama 3 Local — Optimization Test Plan

This plan builds on the [Step 1 baseline](step1-baseline.md). We measure every experiment with the same scorecard
(section 0), so that each change ends up as one row: what it gained in speed or memory, and what it cost in quality.
This document records the plan as we wrote it before running the experiments; the outcomes are in
[RESULTS.md](../RESULTS.md).

**Principles.** We change one variable at a time. We keep the baseline configuration fixed and re-run it whenever the
build changes. Failures (OOM, runaway chunks) are reported as results, not dismissed as noise.

## Status

| # | Experiment | Effort | Status |
|---|---|---|---|
| 0 | Scorecard harness | small | not started |
| 1 | Thread sweep | small | not started |
| 2 | Load-time profiling | small | not started |
| 3 | mmap loader + RAM-cap sweep (SSD streaming) | project | not started |
| 4 | Expert-usage profiling → hot/warm/cold tiering | project | not started |
| 5 | Mixed-precision / imatrix quant | project | not started |
| 6 | CUDA vs Vulkan | small–medium | not started |

The recommended order is 0 → 1 → 2 → 3 → 4 → 5, with 6 whenever convenient. The tiering in item 4 depends on the mmap
loader from item 3, but its profiling step does not.

## Controls (every run)

- WSL `.wslconfig`: `memory=28GB`, `swap=0`. This has been the standing configuration since 2026-10-19, and we do not
  restore the old settings after each test. Only an experiment that varies the cap changes it, and it returns to 28 GB
  afterwards.
- ComfyUI and other GPU apps are closed. We record baseline VRAM before each run (≈0.5 GB for the desktop).
- We record the page-cache state, cold (after `wsl --shutdown`) or warm, and report load time separately from
  generation time.
- Each comparison uses the same binary (git tag and build flags recorded), the same model file, and `--voice none`
  unless voices are being tested.
- Harness: `~/drama3/run.sh TAG SEED`. It records `/usr/bin/time -v`, nvidia-smi every 1 s, vmstat 1, /proc RSS every
  1 s and smaps_rollup. Results go in `~/drama3/runs/<tag>/`.

## 0. Scorecard harness

**Corpus.** 20 fixed English sentences (a mix of short, long, questions, numbers and names), plus the cold-open
narration paragraph. Each sentence is passed as its own line so that chunking cannot hide runaways. Seeds 1, 2, 3.

**Metrics per take:**

| Metric | Tool | What it catches |
|---|---|---|
| CER / WER | `speech asr qwen3-asr-1.7b` (in speech.cpp); Whisper large-v3 as a cross-check | wrong, skipped or repeated words; babble |
| Predicted MOS | UTMOSv2 | naturalness, artifacts |
| Speaker similarity | WavLM/ECAPA embedding cosine, chunk against chunk | voice drift across chunks |
| Sanity | duration ÷ word count, silence share, `max_seconds` stop reason | runaway chunks, dead air |
| Speed | RTFx, s/frame, time to first audio, load time | — |
| Memory / I/O | peak RSS (anon vs file), peak VRAM, disk MB/s during generation | — |

**Fidelity test (for comparing variants).** We teacher-force one fixed token sequence through F16 and the variant, and
report the per-step KL divergence and top-1 agreement of the next-token distribution. This removes sampling randomness
and isolates what the variant changed. It needs a small speech.cpp patch to dump logits; speech.cpp's existing
`*-check` tools are the model to follow.

**Done when** a single command produces a table for one configuration, and two runs of the baseline agree within noise
(CER ±1 pt, RTFx ±5%).

**Listening.** Blind A/B tests are reserved for finalists. Automatic metrics rank the candidates; ears make the final
call.

## 1. Thread sweep

- **Hypothesis:** the CPU experts are under-threaded (only about 4 of 16 threads are busy at the default).
- **Procedure:** run `--threads 4, 8, 12, 16`, three seeds each, on the sentence corpus, recording CPU% and, where
  available, memory-bandwidth counters.
- **Read-out:** s/frame against threads. If the curve is flat after 8, the workload is memory-bandwidth bound (DDR4 ≈
  40–50 GB/s). If it keeps scaling, we set a new default.
- **Pass:** a clear best thread count. Any gain of 10% or more is adopted as the baseline for later experiments.

## 2. Load-time profiling

- **Hypothesis:** the 2–6 min load is not limited by the disk (60–160 MB/s against 1–1.8 GB/s from fio). The likely
  causes are single-threaded `fread`, CPU repacking or the GPU upload.
- **Procedure:** time each phase (metadata, fread per backend, upload) with `perf` or with timestamps added in
  `model-file.cpp`, and compare cold and warm page cache.
- **Pass:** the load-time bottleneck is identified, with a proposed fix (parallel reads, larger reads, a pinned upload
  buffer). A workaround worth measuring regardless is to keep one `speech worker` alive and measure the per-request cost
  without the load.

## 3. mmap loader + RAM-cap sweep (SSD streaming)

- **Goal:** answer the original question of how much speed is lost per GB of RAM taken away, when weights page in from
  the QLC SSD.
- **Change:** load the CPU-side tensors from an mmap of the GGUF (borrowing llama.cpp's `llama_mmap` approach, since
  both use ggml), so that they are file-backed and evictable.
- **Checks first:** the output is bit-identical to the fread build at the same seed, and smaps shows the CPU experts as
  `Pss_File`, not anon.
- **Sweep:** WSL memory cap 28, 24, 20, 16, 12, 8 GB (swap 0). At each cap we record s/frame, major faults/frame, disk
  MB/s and read size during generation, and whether the run completes.
- **Variants:** `madvise(MADV_RANDOM)` against the default readahead, and the readahead size
  (`/sys/block/*/queue/read_ahead_kb`).
- **Expectation:** speed falls steeply once the cap drops below about 16 GB. A miss costs about 1.75 MB per expert,
  roughly 2–5 ms as page faults. Startup and repeat runs should become much faster, since there is no copy and the page
  cache stays warm.
- **Pass:** a curve of speed against RAM cap, plus the minimum RAM at which the model runs at ≥0.1× realtime.
- **Failure paths to test:** a cap so low that even the non-expert weights do not fit (it should fail cleanly, not
  hang), and the file changing under the mmap (refuse or detect).

## 4. Expert-usage profiling → tiering

- **Step 4a, profiling (cheap, and informative on its own):** log the router picks (layer, expert) per frame over 10–20
  min of English narration, plus a contrasting set (Japanese; cues like `[whispers]`, `[laughs]`; multi-speaker).
- **Read-outs:** the frequency curve per layer, the share of picks covered by the top N experts, the overlap between
  workloads, and temporal locality (how often frame t+1 reuses frame t's experts).
- **Decision gate:** if about 30% of experts cover ≥98% of English-narration picks, we build tiering. If routing is
  spread out, we write that up as the result and stop there.
- **Step 4b, tiering:** fill spare VRAM with the hottest experts from all 40 layers instead of 4 whole layers. Warm
  experts stay in RAM, and cold ones stay on the SSD through the mmap from experiment 3.
- **Measure:** s/frame, misses/frame, RAM need, the scorecard, and the fidelity test (the outputs should be identical,
  since tiering moves weights without changing them).
- **Stretch:** a pruned "English narration" variant that drops never-used experts. Its quality must be checked with
  CER, MOS, KL and listening, because pruning changes outputs.
- **Prior art:** Fiddler, MoE-Infinity (expert offload and caching), HOBBIT (cold experts at low precision), REAP
  (expert pruning).

## 5. Mixed-precision / imatrix quant

- **Change:** extend `speech quantize`, which today supports only f16/q8_0/q6_k/q5_k/q4_k, one uniform type, from an
  F32 source, with no imatrix. We add per-tensor rules (attention, router, shared expert and embeddings at Q6_K/Q8_0;
  routed experts at Q3_K or IQ types) and an importance matrix computed from sample text.
- **Source:** the published F16 (71.6 GB), converted to F32 (about 143 GB of the roughly 700 GB free).
- **Variants:** experts at Q4_K (control), Q3_K, IQ3 and IQ4_XS, each with and without the imatrix.
- **Measure:** file size, the number of expert layers the GPU now holds, s/frame, RSS, the scorecard, and KL against
  F16.
- **Pass:** a variant that is smaller and/or faster, with KL and CER no worse than the published Q4_K's distance from
  F16.
- **Expected gain:** going from 21 GB to about 15 GB should let the GPU hold perhaps 6–8 layers' experts, for maybe
  10–20% more speed and less RAM.
- **Publishing:** if the result is worth sharing, we upload it to Hugging Face with a model card, keeping the Fish
  Audio Community License and the "Built with Fish Audio" notice.

## 6. CUDA vs Vulkan

- Upstream only checks Vulkan. Under WSL, Vulkan on NVIDIA goes through a translation layer (dzn), so a fair Vulkan run
  requires a native Windows build. We use the same model, corpus and seeds, and compare s/frame, VRAM, the expert-layer
  split and the scorecard.

## Side items

- Runaway chunks: test one sentence per line, a lower `--max-seconds`, and a voice file against `--voice none`, and
  record the rate of `max_seconds` stops across the corpus.
- Licence: Fish Audio Community License 1.0. Commercial use is permitted under $500k/yr revenue; a TTS service for
  others needs an agreement.
