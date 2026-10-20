# Results

Measured 2026-10-19 on one PC: RTX 4060 Ti 8 GB, Ryzen 7 5700 (8C/16T), 32 GB DDR4, Crucial P3 2 TB (QLC, DRAM-less
NVMe), Windows 11 with WSL2 Ubuntu 22.04 (memory=28GB, swap=0). Model: Fish Audio Drama 3, 35B-A3B, the published Q4_K
GGUF (20.8 GB) and our expert-quant variants made from the published F16. Runtime: speech.cpp main at `eacabcd` plus the
[patches](patches/). Method and pass/fail criteria: [docs/test-plan.md](docs/test-plan.md).

RTFx is audio seconds per wall-clock second of generation (1.0 = realtime). WER/CER come from Qwen3-ASR 1.7B. UTMOS is an
automatic MOS predictor (1–5).

## Summary

**Best setup on this PC: native Windows Vulkan, mmap loader with prefetch, Q2_K routed experts. 0.70× realtime, ready in
11 s, 7.4 GB of RAM.** That is +60% over the stock build under WSL (0.44×) and +12% over the stock Windows release
(0.63×), at half the RAM. [`narrate.cmd`](narrate.cmd) uses it.

1. **mmap loader: worker ready in seconds, not minutes, at a fraction of the RAM.** 8.6 s warm / 57 s cold against
   224–302 s, 0.5 GB of anonymous memory against 16.4 GB, bit-identical output, and it runs under a 16 GB cap where the
   stock loader was OOM-killed.
2. **The speed limit is the GPU↔CPU handoff, about 1.1 ms per CPU-computed layer per frame**, not CPU compute. Threads,
   polling and moving individual hot experts to the GPU barely move it. Fewer CPU layers (smaller experts, so more
   layers fit in VRAM) and a cheaper handoff (native Windows instead of WSL) do.
3. **SSD streaming works but costs speed**, and router-driven prefetch recovers most of it: 1.5–2.25× faster under a
   RAM cap, with 7× fewer page faults.
4. **Q2_K experts are the best trade**: 1.4× faster at 55% of the RAM, for about +0.6 WER points in English and +1.7
   kana-CER points in Japanese. Bi's blind listening test rated it highest of five builds. Plain Q3_K (no imatrix) was
   worst on both public benchmarks and the listening test despite a lower KL.
5. **Expert routing is broad**: 90% of experts are used and the hot set is not workload-specific, so there is no small
   subset to prune or pin.

| setup | RTFx | ready | RAM | GPU expert layers |
|---|---|---|---|---|
| stock, CUDA in WSL, Q4_K | 0.44 | 287 s | 16.1 GB | 4 |
| mmap build, CUDA in WSL, Q4_K | 0.50 | 18 s | 14.6 GB (file-backed) | 4 |
| stock v0.8.10 release, Vulkan on Windows, Q4_K | 0.63 | 44 s | 15.2 GB | 5 |
| patched, Vulkan on Windows, Q4_K, mmap + prefetch | 0.65 | 15 s | 14.2 GB | 5 |
| **patched, Vulkan on Windows, Q2_K experts, mmap + prefetch** | **0.70** | **11 s** | **7.4 GB** | 9 |

## Step 1: baseline

Full write-up: [docs/step1-baseline.md](docs/step1-baseline.md).

- **No streaming out of the box.** speech.cpp reads the GGUF with `fread` into allocated buffers. smaps showed 16.06 GB
  anonymous against 0.08 GB file-backed, so the kernel could not evict the CPU-side experts and re-read them.
- On 8 GB the GPU holds the experts of 4 of 40 layers; the CPU computes the other 36.
- 0.4× realtime (0.10–0.13 s per 46 ms frame), first audio at 16–25 s, load 129–358 s at only 60–160 MB/s.
- Peak RSS 16.0 GB, peak VRAM 7.3 of 8 GB.
- **Under a 16 GB WSL cap the load was OOM-killed** after 40 s. It did not fall back to the SSD.
- Seed 1 of 3 was clean. Seeds 2 and 3 each had a chunk run to the 47.6 s cap (dead air, murmuring).
- SSD, fio random read, direct: 969 MB/s at 4 MiB QD1, 1802 MB/s at QD8.

Model structure: 40 text layers, each with 256 routed experts (8 picked per token) plus a shared expert. A frame uses 320
of 10,240 expert slots (about 3%). An expert is about 1.75 MB at Q4_K, and the experts are about 18 GB of the 20.8 GB file.

## Round 1

### Scorecard baseline (Q4_K, CUDA in WSL, 8 threads, 20 sentences + 1 paragraph × 3 seeds)

| WER | sentence WER | CER | flagged | RTFx | first audio p50 | load | peak RSS | peak VRAM | UTMOS |
|---|---|---|---|---|---|---|---|---|---|
| 3.8% | 1.6% | 3.3% | 5 / 63 | 0.49 | 0.63 s | 256 s | 16.1 GB | 7.3 GB | 4.41 |

- Generation is deterministic: the same seed gives the same samples across thread counts and loaders.
- The paragraph runaways (seeds 2 and 3) dropped most of the script (66% and 79% WER). Voice-drift similarity (0.53
  clean against 0.18 / 0.05 bad) detects these failures; UTMOS caught only one.
- "Honestly? I have no idea." came out as "Honestly." "Wait. Did you hear that?" got 2–4 s pauses.

### Threads

| threads | 4 | 8 | 12 | 16 |
|---|---|---|---|---|
| RTFx | 0.49 | 0.44 | 0.44 | 0.36 |

Outputs were identical. The CPU experts read about 0.5 GB per frame, around 5 GB/s, far below DDR4 bandwidth, so the CPU
is not the limit. Use 4–8 threads.

### Load profiling and the mmap loader (`SPEECH_LOAD_TIMING`, `SPEECH_MMAP`)

| loader / cache | load | CPU tensors read | CPU copy | GPU tensors read | worker ready |
|---|---|---|---|---|---|
| fread cold | 196 s | 16.3 GB in 72 s (228 MB/s) | 75 s | 4.5 GB in 46 s | 224 s |
| fread "warm" | 277 s | 121 s | 130 s | 23 s | 302 s |
| mmap cold | 24 s | paged on use | — | 21 s | 57 s |
| mmap warm | 5.8 s | — | — | 4.9 s (918 MB/s) | 8.6 s |

With fread the file sits in RAM twice (page cache plus the 16 GB anonymous copy). In a 27 GB VM the two evict each
other, so a "warm" cache loads slower than a cold one. First-touch faults into fresh anonymous memory run at about
217 MB/s under WSL. The mmap loader avoids both, and its output has the same MD5 as the stock loader's.

### RAM-cap sweep (mmap, cgroup `MemoryMax`, cold cache, 5 sentences)

| cap | RTFx | resident | major faults | read during run |
|---|---|---|---|---|
| none | 0.32 | 14.6 GB | 0.63 M | 18.7 GB |
| 16 GB | 0.35 | 14.6 GB | 0.63 M | 18.7 GB |
| 12 GB | 0.22 | 11.8 GB | 1.17 M | 29.6 GB |
| 10 GB | 0.13 | 9.7 GB | 2.10 M | 50.7 GB |
| 8 GB | 0.08 | 7.7 GB | 2.96 M | 73.7 GB |

The working set is about 14.6 GB. These RTFx values include cold-start page-in (warm mmap reaches 0.50). Page-fault
reads managed only 140–210 MB/s against 1–1.8 GB/s from fio.

**Readahead** (10 GB cap): `read_ahead_kb` 128 (default) 0.136, 1024 0.110, 4096 0.062, 128 + `MADV_RANDOM` 0.040.
Each expert slice is contiguous, so a small readahead pays and a large one wastes scarce RAM.

### Expert routing (`SPEECH_EXPERT_LOG`, 2,938 frames of English)

- 9,246 of 10,240 experts (90%) were used. Per layer, the top 5 / 10 / 20 / 30 / 50% covered 27 / 42 / 61 / 74 / 89% of picks.
- Frame-to-frame reuse in the same layer was 28%.
- A global hot set of 1 / 2 / 4 GB covers 30 / 46 / 66% of picks.
- An LRU simulation predicts 175 / 116 / 44 / 10 misses per frame for 2 / 4 / 8 / 12 GB caches, consistent with the sweep.
- The English top 30% covers 70% of picks in Japanese, Spanish, whispered, laughing and multi-speaker text. The pruning
  gate (≥98% of picks covered by ≤30% of experts) fails.

### Hot-expert GPU tiering (`SPEECH_HOT_EXPERTS`, `SPEECH_HOT_GB`)

| run | RTFx | text model ms/frame | sentence WER |
|---|---|---|---|
| default (4 GPU layers) | 0.496 | 69.1 | 4.7% |
| 1.7 GB hot (1,031 experts) | 0.523 | 71.5 | 4.5% |
| 2.2 GB hot (1,334 experts) | 0.539 | 68.6 | 0.7% |
| 1.0 GB hot | non-finite logits | | |

At best +8%, and unstable: some sizes produce NaN logits (probably an uninitialised read in the device hot-copy path;
unresolved). The overhead check explains why it can't do more: 36 CPU layers cost 59.7 ms of text model per frame and
40 cost 64.0, so each CPU layer costs about 1.1 ms whatever share of its picks moves to the GPU. A frame (about 84 ms)
splits into text model 60–69 ms (about 39 ms of that is CPU-layer handoff), audio decoder 10 ms, codec 3 ms.

## Mixed-precision expert quants

Made with the patched `speech quantize` from the published F16 file: base type Q4_K, only the routed experts (`_exps`)
changed, router F32.

**KL fidelity**, teacher-forced: Q4_K recorded 2 trajectories (60 frames each), F16 replayed them on the CPU, each variant
replayed them on the GPU. Mean KL(F16 ‖ variant):

| experts | file | main-token KL | codebook KL | main top-1 agree |
|---|---|---|---|---|
| Q4_K (published) | 20.8 GB | 0.068 | 0.156 | 67% |
| Q4_K (our control, from F16) | 20.8 GB | 0.066 | 0.158 | 67% |
| IQ4_XS | 19.8 GB | 0.068 | 0.158 | 69% |
| Q3_K | 16.5 GB | 0.090 | 0.165 | 68% |
| IQ3_S (no imatrix) | 16.5 GB | 0.117 | 0.180 | 63% |
| Q2_K | 13.2 GB | 0.191 | 0.195 | 53% |

Q4_K replaying its own recording gives KL 0.00000 and 100% agreement (this check caught and fixed an off-by-one in the
codebook indices). The control matches the published file, so quantising from F16 costs nothing measurable. This is a
small sample: 2 sentences, 120 frames.

**Speed and scorecard** (CUDA in WSL, 20 sentences × 2 seeds, mmap, warm cache):

| experts | GPU expert layers | RTFx | text ms/frame | RAM resident | sentence WER | runaways | UTMOS |
|---|---|---|---|---|---|---|---|
| Q4_K (control) | 4 | 0.39–0.50 | 69–88 | 15.2 GB | 0.4% | 0 | 4.46 |
| IQ4_XS | 5 | 0.43 | 83 | 14.1 GB | 0.7% | 0 | 4.44 |
| Q3_K | 6 | 0.59 | 60 | 11.3 GB | 3.1% | 1 / 40 | 4.42 |
| IQ3_S | 6 | 0.49 | 72 | 11.2 GB | 1.6% | 1 / 40 | 4.43 |
| Q2_K | 8 | 0.65 | 53 | 8.3 GB | 0.4% | 0 | 4.43 |

Smaller experts let more layers fit on the GPU (4 → 8) and roughly halve resident RAM, consistent with the fixed cost
per CPU layer. Treat speed as ±15% (cache disturbance between runs). UTMOS does not separate the variants.

## Native Windows build

The official v0.8.10 Windows Vulkan release (SHA-256 verified) with the published Q4_K, the same 20 sentences, seed 1,
WSL shut down:

| setup | RTFx | first audio | ready | GPU expert layers | sentence WER | UTMOS |
|---|---|---|---|---|---|---|
| stock, CUDA in WSL | 0.44 | 0.73 s | 287 s | 4 | 4.7% | — |
| mmap build, CUDA in WSL | 0.50 | 0.86 s | 18 s | 4 | 4.7% | 4.43 |
| **stock, Vulkan, native Windows** | **0.63** | 0.53 s | 44 s | 5 | 0.7% | 4.47 |

The extra GPU layer is worth only about 1 ms per frame. The rest of the roughly 20 ms per frame saved is cheaper
synchronisation outside WSL's GPU paravirtualisation.

We then built the patches natively (MSVC Build Tools 2022, Vulkan SDK 1.4.363.0; steps in
[docs/build-windows.md](docs/build-windows.md)). The mmap loader gained a Win32 path:

| run | RTFx | ready | RAM (working set) | GPU expert layers | text ms/frame |
|---|---|---|---|---|---|
| stock v0.8.10 release, Q4_K | 0.629 | 44 s | 15.2 GB | 5 | — |
| patched, Q4_K, fread | 0.629 | 23 s | 15.1 GB | 5 | 54 |
| patched, Q4_K, mmap (first try) | 0.465 | 32 s | 14.2 GB | 5 | 62 |
| **patched, Q4_K, mmap + prefetch** | **0.654** | **15 s** | 14.2 GB | 5 | 52 |
| patched, Q2_K experts, fread | 0.711 | 18 s | 7.9 GB | 9 | 39 |
| **patched, Q2_K experts, mmap + prefetch** | **0.702** | **11 s** | **7.4 GB** | 9 | 40 |

The first Win32 mmap opened the file with `FILE_FLAG_RANDOM_ACCESS`, which disables read-ahead, and paid a soft fault
per page. Dropping the flag and calling `PrefetchVirtualMemory` on the view (llama.cpp's approach) made mmap faster than
fread. With Q2_K, 9 expert layers fit on the GPU instead of 5, and text-model time drops from 52 to 40 ms per frame.

## Expert prefetch from the router (`SPEECH_PREFETCH_EXPERTS`)

A CPU custom op passes the router's picks through and asks the OS to read the chosen experts' slices
(`madvise(MADV_WILLNEED)`, `PrefetchVirtualMemory` on Windows) before they compute. `same` covers the layer's own picks;
`next` also guesses the next layer's picks by running its router on this layer's input. Output is bit-identical.

CUDA in WSL, mmap, cgroup cap, cold cache, 5 sentences:

| cap | none | **same** | next | major faults none → same | read MB/s none → same |
|---|---|---|---|---|---|
| 12 GB | 0.21 | **0.32** (1.5×) | 0.25 | 1.17 M → 0.17 M | 182 → 254 |
| 10 GB | 0.10 | **0.23** (2.2×) | 0.18 | 2.09 M → 0.30 M | 169 → 311 |
| 8 GB | 0.08 | **0.18** (2.25×) | 0.13 | 2.99 M → 0.40 M | 194 → 333 |

- Same-layer prefetch turns about 7× more page faults into batched, parallel reads and nearly doubles the SSD throughput
  used. At 12 GB it matches the uncapped cold-start speed.
- Next-layer guessing is worse: only 53.7% of guesses were then picked (38–41% in the weakest layers), and the wrong
  ones spend bandwidth and evict useful pages. A better predictor could change that.
- Q2_K experts (7.4 GB working set) with same-layer prefetch under a cap near 8 GB is not yet measured.

## Public benchmarks

**speech-bench Japanese**: its `speak-ja-JP` prompts, 20 × seeds 1–3, Qwen3-ASR 1.7B (the judge of speech.cpp's
published table), voice `none` (upstream's reference voice is not published). CER is pooled over kana readings
(OpenJTalk on both sides), an automatic stand-in for speech-bench's hand-annotated accepted spellings; plain CER was
12–16%, almost all spelling (24 against 二十四).

| experts | pooled kana CER | takes >10% | RTFx |
|---|---|---|---|
| published reference, Q4_K (H100, reference voice) | 1.5% | — | — |
| Q4_K | 2.5% | 9 / 60 | 0.59 |
| IQ4_XS | 2.7% | 11 / 60 | 0.55 |
| Q2_K | 4.2% | 9 / 60 | 0.73 |
| Q3_K | 7.8% | 15 / 60 | 0.61 |

**LibriSpeech test-clean English**: a fixed 100-utterance subset (8–25 words), seed 1.

| experts | WER | CER | flagged | RTFx | RAM | UTMOS |
|---|---|---|---|---|---|---|
| Q4_K | 1.7% | 0.8% | 3 | 0.52 | 15.5 GB | 4.36 |
| Q3_K | 2.7% | 1.9% | 8 (1 runaway) | 0.63 | 11.4 GB | 4.33 |
| Q2_K | 2.3% | 1.2% | 5 | 0.72 | 8.4 GB | 4.31 |

On both, plain Q3_K came out worse than Q2_K despite its lower KL. IQ4_XS is equivalent to Q4_K.

## Blind listening test

6 sentences × 5 builds, seed 1, voice `none`, takes labelled A–E and shuffled per sentence, scored 1–5 by Bi before
seeing the key.

| build | mean | s04 | s06 | s10 | s11 | s14 | s19 |
|---|---|---|---|---|---|---|---|
| Q2_K experts | **3.50** | 3 | 4 | 3 | 3 | 4 | 4 |
| Q4_K (published) | 2.83 | 3 | 3 | 2 | 2 | 3 | 4 |
| IQ3_S experts | 2.83 | 3 | 3 | 2 | 3 | 3 | 3 |
| IQ4_XS experts | 2.50 | 3 | 3 | 2 | 2 | 2 | 3 |
| Q3_K experts | 2.33 | 3 | 3 | 1 | 2 | 2 | 3 |

- Q2_K was never scored below another build on any sentence and was highest or joint highest on all six. With 6 takes
  per build this is not statistically meaningful, and each build draws a different sample, so seed luck is in it.
- Q3_K was lowest, agreeing with both public benchmarks.
- Scores overall are middling (2.3–3.5, "noticeable issue but usable"): voice `none` English from this model is not
  narrator-grade to Bi's ear whatever the build. Q2_K's higher KL is not audible as worse in this sample.

## What it means, and what's next

- Use the mmap loader. It starts in seconds, halves RAM, and can run next to other GPU apps.
- On an 8 GB card the ceiling is set by the CPU-layer handoff. Real speedups need fewer CPU layers (smaller expert
  quants, more VRAM) or a cheaper handoff (native Windows; fused CPU kernels or asynchronous overlap in the scheduler).
  Moving individual experts doesn't help.
- Next: find what the listening issues are (prosody, artifacts, pacing) and test reference-voice files; an importance
  matrix for the IQ quants; KL on more sentences; Q2_K + prefetch under an 8 GB cap; a better next-layer predictor.
