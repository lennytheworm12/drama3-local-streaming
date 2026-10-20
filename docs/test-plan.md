# Drama 3 Local — Optimization Test Plan

Builds on the [Step 1 baseline](step1-baseline.md). Every experiment is measured with the
same scorecard (section 1), so each change ends up as one row: what it gained in speed or memory, and
what it cost in quality.

**Principles.** Change one variable at a time. Keep the baseline config fixed and re-run it
whenever the build changes. Report failures (OOM, runaway chunks) as results, not as noise.

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

Recommended order: 0 → 1 → 2 → 3 → 4 → 5, with 6 whenever convenient. Item 4's tiering depends
on 3's mmap loader; 4's profiling step does not.

## Controls (every run)

- WSL `.wslconfig`: `memory=28GB`, `swap=0`. This is the standing config as of 2026-10-19 (Bi: keep it,
  don't restore after each test). Only an experiment that varies the cap changes it, and it
  returns to 28 GB afterwards.
- ComfyUI and other GPU apps closed. Record baseline VRAM before each run (≈0.5 GB desktop).
- Record page-cache state: cold (after `wsl --shutdown`) or warm. Report load time separately
  from generation time.
- Same binary (git tag + build flags recorded), same model file, `--voice none` unless testing voices.
- Harness: `~/drama3/run.sh TAG SEED`. It records `/usr/bin/time -v`, nvidia-smi every 1 s, vmstat 1,
  /proc RSS every 1 s and smaps_rollup. Results go in `~/drama3/runs/<tag>/`.

## 0. Scorecard harness

**Corpus.** 20 fixed English sentences (mix of short, long, questions, numbers, names), plus the
cold-open narration paragraph. Each sentence goes in as its own line so chunking can't hide
runaways. Seeds 1, 2, 3.

**Metrics per take:**

| Metric | Tool | What it catches |
|---|---|---|
| CER / WER | `speech asr qwen3-asr-1.7b` (in speech.cpp); Whisper large-v3 as a cross-check | wrong, skipped or repeated words; babble |
| Predicted MOS | UTMOSv2 | naturalness, artifacts |
| Speaker similarity | WavLM/ECAPA embedding cosine, chunk against chunk | voice drift across chunks |
| Sanity | duration ÷ word count, silence share, `max_seconds` stop reason | runaway chunks, dead air |
| Speed | RTFx, s/frame, time to first audio, load time | — |
| Memory / I/O | peak RSS (anon vs file), peak VRAM, disk MB/s during generation | — |

**Fidelity test (for comparing variants).** Teacher-force one fixed token sequence through
F16 and the variant. Report per-step KL divergence and top-1 agreement of the next-token
distribution. This removes sampling randomness and isolates what the variant changed. It needs a
small speech.cpp patch to dump logits; speech.cpp's existing `*-check` tools are the model to follow.

**Done when** a single command produces a table for one config, and two runs of the baseline agree
within noise (CER ±1 pt, RTFx ±5%).

**Listening.** Blind A/B only for finalists. Automatic metrics rank; ears decide.

## 1. Thread sweep

- **Hypothesis:** the CPU experts are under-threaded (only about 4 of 16 threads busy at the default).
- **Procedure:** `--threads 4, 8, 12, 16`, three seeds each, on the sentence corpus. Also record
  CPU% and, if available, memory-bandwidth counters.
- **Read-out:** s/frame against threads. If it's flat after 8 → memory-bandwidth bound (DDR4 ≈ 40–50
  GB/s). If it keeps scaling → set a new default.
- **Pass:** a clear best thread count. Any gain of 10% or more is adopted as the baseline for later experiments.

## 2. Load-time profiling

- **Hypothesis:** the 2–6 min load isn't limited by the disk (60–160 MB/s against 1–1.8 GB/s fio). The likely
  causes are single-threaded `fread`, CPU repacking or GPU upload.
- **Procedure:** time each phase (metadata, fread per backend, upload), with `perf` or timestamps added
  in `model-file.cpp`. Compare cold and warm page cache.
- **Pass:** the load-time bottleneck is identified, with a proposed fix (parallel reads, larger
  reads, pinned upload buffer). A workaround to measure regardless: keep one `speech worker` alive
  and measure per-request cost without the load.

## 3. mmap loader + RAM-cap sweep (SSD streaming)

- **Goal:** answer the original question, how much speed is lost per GB of RAM taken away,
  when weights page in from the QLC SSD.
- **Change:** load CPU-side tensors from an mmap of the GGUF (borrow llama.cpp's `llama_mmap`
  approach; both use ggml), so they are file-backed and evictable.
- **Checks first:** output is bit-identical to the fread build at the same seed. smaps shows the CPU
  experts as `Pss_File`, not anon.
- **Sweep:** WSL memory cap 28, 24, 20, 16, 12, 8 GB (swap 0). At each cap record s/frame, major
  faults/frame, disk MB/s and read size during generation, and whether it completes.
- **Variants:** `madvise(MADV_RANDOM)` vs default readahead, and readahead size
  (`/sys/block/*/queue/read_ahead_kb`).
- **Expectation:** speed falls steeply once the cap drops below about 16 GB. A miss costs about 1.75 MB per expert,
  roughly 2–5 ms as page faults. Startup and repeat runs should get much faster: no copy, and a warm page cache.
- **Pass:** a curve of speed against RAM cap, plus the minimum RAM at which it runs at ≥0.1× realtime.
- **Failure paths to test:** a cap so low that even the non-expert weights don't fit (it should fail
  cleanly, not hang), and the file changing under the mmap (refuse or detect).

## 4. Expert-usage profiling → tiering

- **Step 4a, profiling (cheap, informative on its own):** log router picks (layer, expert) per
  frame. Run 10–20 min of English narration, plus a contrasting set (Japanese; cues like
  `[whispers]`, `[laughs]`; multi-speaker).
- **Read-outs:** frequency curve per layer, the share of picks covered by the top N experts, overlap
  between workloads, and temporal locality (how often frame t+1 reuses frame t's experts).
- **Decision gate:** if about 30% of experts cover ≥98% of English-narration picks, build tiering.
  If routing is spread out, write that up as the result and stop there.
- **Step 4b, tiering:** fill spare VRAM with the hottest experts from all 40 layers, instead of 4
  whole layers. Keep warm experts in RAM and leave cold ones on the SSD through the mmap from experiment 3.
- **Measure:** s/frame, misses/frame, RAM need, the scorecard, and the fidelity test (the outputs
  should be identical, since tiering moves weights but doesn't change them).
- **Stretch:** a pruned "English narration" variant that drops never-used experts. Quality
  must be checked with CER, MOS, KL and listening, because pruning changes outputs.
- **Prior art to read:** Fiddler, MoE-Infinity (expert offload and caching), HOBBIT (cold experts
  at low precision), REAP (expert pruning).

## 5. Mixed-precision / imatrix quant

- **Change:** extend `speech quantize` (today it supports only f16/q8_0/q6_k/q5_k/q4_k, one uniform type,
  from an F32 source, and no imatrix). Add per-tensor rules: attention, router, shared expert and
  embeddings at Q6_K/Q8_0, routed experts at Q3_K or IQ-types. Add an importance matrix
  from sample text.
- **Source:** the published F16 (71.6 GB), converted to F32 (about 143 GB of the roughly 700 GB free).
- **Variants:** experts at Q4_K (control), Q3_K, IQ3 and IQ4_XS, each with and without the imatrix.
- **Measure:** file size, layers of experts the GPU now holds, s/frame, RSS, scorecard, KL
  against F16.
- **Pass:** a variant that is smaller and/or faster with KL and CER no worse than published
  Q4_K's distance from F16.
- **Expected gain:** 21 GB → about 15 GB lets the GPU hold perhaps 6–8 layers' experts, for maybe 10–20%
  more speed and less RAM.
- **Publishing:** if worth sharing, upload to Hugging Face with a model card. Keep the Fish Audio
  Community License and the "Built with Fish Audio" notice.

## 6. CUDA vs Vulkan

- Upstream only checks Vulkan. Under WSL, Vulkan on NVIDIA goes through a translation layer
  (dzn), so build natively on Windows for a fair Vulkan run. Same model, corpus and seeds.
  Compare s/frame, VRAM, the expert-layer split and the scorecard.

## Side items

- Runaway chunks: test one sentence per line, `--max-seconds` lower, and a voice file against
  `--voice none`. Record the rate of `max_seconds` stops across the corpus.
- License: Fish Audio Community License 1.0. Commercial use is OK under $500k/yr revenue; a TTS
  service for others needs an agreement.

