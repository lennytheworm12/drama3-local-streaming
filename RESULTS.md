# Results

Measured 2026-10-19 and 20 on one PC: RTX 4060 Ti 8 GB, Ryzen 7 5700 (8C/16T), 32 GB DDR4, Crucial P3 2 TB (QLC, DRAM-less
NVMe), Windows 11 with WSL2 Ubuntu 22.04 (memory=28GB, swap=0). Model: Fish Audio Drama 3, 35B-A3B, the published Q4_K
GGUF (20.8 GB) and our expert-quant variants made from the published F16. Runtime: speech.cpp main at `eacabcd` plus the
[patches](patches/). Method and pass/fail criteria: [docs/test-plan.md](docs/test-plan.md).

RTFx is audio seconds per wall-clock second of generation (1.0 = realtime). WER/CER come from Qwen3-ASR 1.7B. UTMOS is an
automatic MOS predictor (1–5).

## Summary

**Best setup on this PC: native Windows Vulkan with an English-imatrix Q4_K, the fused audio decoder, half-precision
caches sized for a line, `token_embd` on the CPU, flash attention and pinned handoff memory.** One take runs at **0.77× realtime** with 8 layers' experts
on the GPU (stock under WSL: 0.44×). Four takes side by side, every expert on the CPU, give **1.24–1.27× realtime
throughput**. [`narrate.cmd`](narrate.cmd) uses the four-stream setup by default. Q2_K experts remain the
low-RAM option (0.70× at 7.4 GB), but a second listening test with a fixed voice found they flatten intonation.

1. **mmap loader: worker ready in seconds, not minutes, at a fraction of the RAM.** 8.6 s warm / 57 s cold against
   224–302 s, 0.5 GB of anonymous memory against 16.4 GB, bit-identical output, and it runs under a 16 GB cap where the
   stock loader was OOM-killed.
2. **The speed limit is the GPU↔CPU handoff, about 1.1 ms per CPU-computed layer per frame**, not CPU compute. Threads,
   polling and moving individual hot experts to the GPU barely move it. Fewer CPU layers (smaller experts, so more
   layers fit in VRAM) and a cheaper handoff (native Windows instead of WSL) do.
3. **SSD streaming works but costs speed**, and router-driven prefetch recovers most of it: 1.5–2.25× faster under a
   RAM cap, with 7× fewer page faults.
4. **Q2_K experts: 1.4× faster at 55% of the RAM, but they cost intonation.** About +0.6 WER points in English and +1.7
   kana-CER points in Japanese. The first blind test (random voices) rated Q2_K highest; the second (one fixed voice)
   preferred Q4_K, 69% against 44% "would watch", and every one of Bi's notes was on a Q2_K take. Q4_K is the quality
   default. Plain Q3_K (no imatrix) was worst on both public benchmarks and the first listening test.
5. **Expert routing is broad**: 90% of experts are used and the hot set is not workload-specific, so there is no small
   subset to prune or pin.
6. **Several takes at once was held back by VRAM, not by the GPU.** Freeing 1.6 GB per stream (F16 cache, caches sized
   for a line, `token_embd` on the CPU) took two streams from 0.80× to 0.98× and made room for four (1.27×).
7. **An English importance matrix halves Q4_K's error at no cost**: main-token KL from F16 0.032 against 0.073 for the
   published Q4_K on 6 held-out sentences, top-token match 83.6% against 75.0%, same size and speed. It is narrate.py's
   default model; Bi's blind listen against the published file is pending.
8. **Many things didn't help**: CPU expert repacking, one graph per frame, op fusion, Vulkan driver switches, Q8_0
   (5–6× slower), self-draft speculative decoding (about 5% acceptance), the shared expert on the GPU beside the CPU
   experts, and a native CUDA build (no faster than Vulkan).

| setup | RTFx | ready | RAM | GPU expert layers |
|---|---|---|---|---|
| stock, CUDA in WSL, Q4_K | 0.44 | 287 s | 16.1 GB | 4 |
| mmap build, CUDA in WSL, Q4_K | 0.50 | 18 s | 14.6 GB (file-backed) | 4 |
| stock v0.8.10 release, Vulkan on Windows, Q4_K | 0.63 | 44 s | 15.2 GB | 5 |
| patched, Vulkan on Windows, Q4_K, mmap + prefetch | 0.65 | 15 s | 14.2 GB | 5 |
| patched, Vulkan on Windows, Q2_K experts, mmap + prefetch | 0.70 | 11 s | 7.4 GB | 9 |
| + fused decoder, Q4_K | 0.69 | | | 4 |
| **+ freed VRAM and flash attention, Q4_K, one take** | **0.77** | | | 8 |
| **+ four takes at once, Q4_K (throughput)** | **1.24–1.27** | about 25 s | | 0 |
| + pinned handoff memory (same-day A/B, slower day) | 0.71 → 0.75 one take, 1.16 → 1.22 four | | | 6 / 0 |

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

## Q4_K speed work on native Windows

After the second listening test made Q4_K the quality default, the work turned to making Q4_K itself faster. All of it is
native Vulkan, built into `build-vk3` with [`scorecard/tools/build_win3.cmd`](scorecard/tools/build_win3.cmd).

### Where a frame goes

`GGML_SCHED_TIMING=1` (Q4_K, 4 GPU expert layers, about 1,000 graphs, synchronised per split):

- GPU compute: 37 splits × 0.50 ms ≈ 18.5 ms. Attention or DeltaNet, router and shared expert, each a tiny one-row dispatch.
- CPU compute: 36 × 0.60 ms ≈ 21.7 ms of routed experts, near DDR4 bandwidth.
- Copies: 0.12 + 0.16 ms per split ≈ 10 ms, about 20%.

The GPU profile (`GGML_VK_PERF_LOGGER`, summarised by [`vk_perf_sum.py`](scorecard/tools/vk_perf_sum.py)) shows about
2,400 ops and 37 ms of GPU time a frame. Matrix-vector products are about 60% of it, at roughly a quarter of the card's
bandwidth because each is small (the m=512 k=2048 Q4_K products take 31 µs each, 126 a frame). Small elementwise ops are
most of the rest, at 5–15 µs each. That kernel-efficiency limit is in ggml, not in our graphs.

### VRAM spill and the GPU-layer cap

With other GPU apps open (about +450 MiB of VRAM), the automatic expert placement overcommitted VRAM. Windows then paged
buffers out: the codec went from 2.5 to 28 ms per frame and overall speed halved (0.65× → 0.35×). `SPEECH_GPU_EXPERT_LAYERS=n`
caps the layers; with n=4 the codec was back to 2.4 ms and speed to 0.60–0.64× with those apps still open. This was also
why a voice file had seemed to cost speed (0.47×): with the cap, 0.636× with the voice against 0.635× without. Under that
memory pressure the mmap path also suffers (Windows trims mapped pages) while fread holds up, so narrate.py now uses fread.

### Fused audio decoder

`SPEECH_FUSED_DECODER=1` puts the decoder's 9 codebook graphs in one and samples on the GPU (argsort top-k, cumsum, step,
one-hot embedding mix). Decoder 11.8 → 8.8 ms per frame, **0.658× → 0.688×**. All 10 sampled takes were bit-identical to
the CPU-sampled path, and top_k=1 too. Adopted.

### Concurrent takes (`SPEECH_STREAMS`)

A pool of synthesizers over the one copy of the weights, each with its own Vulkan and CPU backend, so one take's CPU
experts overlap another's GPU layers. The worker runs n requests at once.

The first try lost (0.50–0.61× for two streams against 0.70× for one): the codec waited behind the other stream's
dispatches and VRAM peaked at 7.5 GB. With the desktop's VRAM lower, two streams × 4 threads with every expert on the CPU
reached 0.79–0.81×, +17% over the best single stream. Three streams ran out of VRAM.

### Freeing VRAM

One stream, every expert on the CPU, measured after warm-up:

| change | VRAM used | saved |
|---|---|---|
| baseline | 4.92 GB | — |
| `SPEECH_KV_F16=1`: keys and values in half precision | 4.46 GB | 0.46 GB |
| + `SPEECH_MAX_PROMPT_ROWS=2048 SPEECH_MAX_FRAMES=1024`: caches and graph buffers for a line instead of 8,192 + 2,048 rows | 3.58 GB | 0.88 GB |
| + `SPEECH_EMBD_ON_CPU=1`: the 0.3 GB `token_embd` in RAM, its row decoded on the CPU | 3.30 GB | 0.28 GB |

The F16 cache's teacher-forced KL against F32 was 0.001–0.003 nats on the main token and under 0.001 on the codebooks, with
92–98% top-1 agreement. Spending the freed memory: two streams went from 0.79–0.81× to **0.98×**, and three streams, out of
VRAM before, reached **1.15×**. Multi-stream had been held back by VRAM, not by the GPU's dispatch latency.

The cost: prompts over 2,048 rows are refused. A line's prompt with the voice file is about 400 rows, so a script needs
one sentence or short paragraph per line.

### Flash attention

`SPEECH_FLASH_ATTN=1` (with the F16 cache, F32 accumulation): text model 52.8 → 48.0 ms and decoder 9.6 → 9.0 ms per frame,
**−5.5 ms (−8%)**, at a KL of 0.003–0.005 against the F16 cache. Adopted.

### Final sweep

Flash attention plus all the VRAM switches. `SPEECH_GPU_EXPERT_LAYERS_EXACT=n` places exactly n layers' experts on the GPU,
because the automatic estimate does not see the smaller caches.

| setup | throughput | VRAM peak |
|---|---|---|
| 1 stream, 6 GPU expert layers | 0.733× | 6.4 GB |
| **1 stream, 8 layers** | **0.769×** | 7.3 GB |
| 2 streams × 4 threads, 4 layers | 1.08× | 6.5 GB |
| 3 streams × 3 threads, 0 / 2 layers | 1.14× / 1.20× | 5.7 / 6.6 GB |
| **4 streams × 2 threads, 0 layers** | **1.27× / 1.24×** (two runs) | 6.6 GB |
| 4 streams × 3 threads | 1.22× | 6.6 GB |
| 4 streams × 2 threads, 1 layer | 1.27× | 7.1 GB |
| 5 streams × 2 threads | 1.16× | 7.5 GB |

narrate.py defaults to 4 streams × 2 threads with every expert on the CPU, and `--streams 1` uses 6 GPU layers to leave
headroom for other apps. The four-line cold open, 2 takes a line with the voice file, took 114 s including load (163 s
before).

### Tried and rejected

| change | result |
|---|---|
| CPU repack (`SPEECH_CPU_REPACK=1`: Q4_K experts in ggml's AVX2 8×8 interleaved layout, as llama.cpp does) | 0.597× against 0.593×. The CPU expert step is not limited by matmul kernel efficiency. |
| Q8_0 (38.5 GB, streamed through mmap) | 0.107–0.132×, 5–6× slower than Q4_K; 40 CPU layers of 8-bit experts at about 294 ms per frame. Not viable on this card, and upstream's CER shows Q8_0 ≈ Q4_K anyway. |
| Audio decoder on the CPU (`SPEECH_DECODER_ON_CPU=1`) | 22.6 ms per frame against 9.25 ms on the GPU, to free 1.4 GB. |
| ggml Vulkan switches (FORCE_MMVQ, ASYNC_USE_TRANSFER_QUEUE, MAX_NODES_PER_SUBMIT=1000, DISABLE_FUSION) | 0.684–0.689× against 0.688×. No effect. |
| Speculative decoding with a self-draft (`SPEECH_SKIP_CPU_EXPERTS=1`: CPU-held layers keep only the shared expert) | Expected acceptance about 5% (main-token top-1 agreement 0%, KL 4.1–4.4 nats) for a draft only 1.5× faster. It would need a trained draft or MTP heads. |
| One submission per frame (`SPEECH_ONE_GRAPH=1`: decoder, embedding, text model and head in one scheduled graph) | Bit-identical, but 64.7 against 64.5 ms per frame. Graph launches were not the cost; the 73 scheduler splits a frame stay either way. |
| Op fusion (`SPEECH_FUSE_OPS=1`: router in llama.cpp's node order for Vulkan's topk_moe kernel, swiglu as one node) | 53.2 against 52.8 ms. Fusing the router lost the sigmoid-mul and multi-add fusions, and the router was about 2% of GPU time. |

### Native Windows CUDA build and utilisation

A native Windows CUDA build (CUDA 13.3.1, sm_89, [`build_cuda.cmd`](scorecard/tools/build_cuda.cmd)) with the same patches and
switches, 20 takes:

| setup | Vulkan | CUDA |
|---|---|---|
| 1 stream, 8 GPU expert layers | 0.769× | 0.773× |
| 3 streams | 1.20× | 1.10× |
| 4 streams | 1.24–1.27× | 1.19× |

NVIDIA's own kernels match Vulkan's, so kernel quality is not the limit, and Vulkan stays the default. With 4 streams the
GPU is busy about 43% of the time and the CPU about 44% (of 16 logical threads; 8 are used): neither side saturates. Each
take stops and starts at 36 GPU↔CPU handoffs a frame, and the CPU experts read about 0.5 GB of RAM a frame (about 14 GB/s
at 4 streams). The remaining cost is GPU idle time waiting on the CPU. Batched multi-take decoding (one handoff per layer for
every take) is the one large throughput lever left, estimated at about 1.5× with a RAM-bandwidth ceiling around 2×.

### Pinned handoff memory and overlap

Single take, 6 GPU expert layers, text-model time per frame, 2 alternating runs:

| change | text ms/frame | takes | verdict |
|---|---|---|---|
| baseline | 51.1 / 51.4 | — | — |
| `SPEECH_SCHED_PINNED=1`: the scheduler's CPU buffers in Vulkan pinned host memory | **48.2 / 48.2** | bit-identical | **adopted** |
| `GGML_SCHED_EARLY=1`: the shared expert built after the router, and the device split's tail submitted once the CPU split has copied its inputs, so the GPU computes it beside the CPU experts | 52.1 / 52.3 | bit-identical | rejected: about 0.1 ms of GPU work per layer, less than an extra submit costs |

A first version that ran the next device split's independent nodes ahead of the CPU split produced NaNs: running nodes out
of the allocator's order lets later nodes reuse memory earlier ones still read. Only contiguous tails are safe.

With pinned memory over 20 takes: one stream 0.712× → **0.752×**, four streams 1.157× → **1.217×** (+5%). These are same-day
runs; that day the PC ran about 5% slower than the final sweep above, with 570 MB of desktop VRAM in use.

The floor for a single take on this rig is about 60 ms per frame: CPU experts about 22 ms, GPU dispatches about 18 ms,
copies about 10 ms, decoder about 9 ms, codec about 2.5 ms. Going lower needs a bigger GPU (more expert layers, fewer
handoffs) or a change to the model's arithmetic.

## English importance-matrix Q4_K

`Drama-imx-q4k.gguf`: 20.8 GB, the same tensor types as the published Q4_K, with each matrix's rounding weighted by how much
its input channels matter on English speech.

- Collection (`SPEECH_IMATRIX_OUT`): an eval callback on every text-model MUL_MAT and MUL_MAT_ID of a `blk.*` weight sums
  each input channel's squares, per expert for the stacked expert tensors.
- Calibration ([`calib.py`](scorecard/tools/calib.py)): 119 English texts (the LibriSpeech subset and the scorecard sentences,
  with the fidelity sentences held out), each with voice `none` and with the narrator voice. 238 runs, 15.8 M products,
  all 520 text-model matrices, 255 of 256 experts per layer.
- Quantising (`SPEECH_QUANT_IMATRIX`, from F16). The audio decoder, codec, `token_embd` and head are not weighted.

KL against F16 on 6 held-out sentences (2 old, 4 new in [`fidelity-extra.txt`](scorecard/fidelity-extra.txt); 60 frames
each; replayed on Vulkan):

| file | main-token KL | main top-1 | codebook KL | codebook top-1 | main KL per sentence |
|---|---|---|---|---|---|
| published Q4_K | 0.0727 | 75.0% | 0.1559 | 53.1% | 0.068 0.056 0.097 0.056 0.107 0.053 |
| **English imatrix Q4_K** | **0.0318** | **83.6%** | **0.1327** | **54.4%** | 0.036 0.028 0.040 0.029 0.035 0.023 |

- −56% main-token KL, better on all 6 sentences, although the trajectories were generated by the published file, which
  biases the test toward it. For scale, Q4_K → Q2_K cost +0.12 KL and was audible.
- Speed and runaways are unchanged: 0 of 20 runaway takes, and the narrated cold open took 118 s against 116 s.
- On the same reference set, the F16 KV cache costs 0.0003 and flash attention 0.0018 in main-token KL against F16.
- Adopted as narrate.py's default model (`--model win\Drama-35B-A3B-v3-Q4_K.gguf` restores the published file).
  **Bi's blind A/B against the published file is pending.**

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

## First blind listening test

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

## Second listening test: fixed voice, Q4_K against Q2_K

The voice was cast from 15 generated candidates. Bi starred 3, and the clear female storyteller (seed 4) was made into a
voice file with `speech voice`. It holds: ECAPA similarity to the reference is 0.77 with the file against 0.15 without.
4 sentences × 4 seeds × 2 builds = 32 blind takes, rated "would watch" plus 1–5.

| build | would watch | mean score | 4+ |
|---|---|---|---|
| **Q4_K (published)** | **11/16 = 69%** | 3.31 | 6 |
| Q2_K experts | 7/16 = 44% | 3.19 | 4 |

- Fisher exact p = 0.29, so not significant at 16 takes each, but the direction favours Q4_K.
- All three of Bi's notes were on Q2_K takes: "too much upwards tone at the end of each word" (twice) and "too monotone".
  That is an intonation defect, consistent with Q2_K's 2.8× KL. The first test's preference for Q2_K was voice luck.
- A fixed voice raised the watch rate from about 20% (first test, random voices) to 56%.
- The voice file lengthens every chunk's prompt. Before the VRAM fixes it cost speed (Q4_K 0.654× → 0.468×); with the
  GPU-layer cap it costs nothing measurable.

## What it means, and what's next

- The English-imatrix Q4_K is the default (pending Bi's listen), the published Q4_K the reference, and Q2_K the speed
  and low-RAM option.
- On an 8 GB card a single take is near its floor (0.77×). Throughput comes from running takes side by side, which
  suits narration, since several takes per line are wanted anyway.
- Use the mmap loader when RAM is short; fread is steadier when other apps press on memory on Windows.
- Next: Bi's blind listen of the imatrix Q4_K; batched multi-take decoding (one handoff per layer for every take), the
  remaining throughput lever; imatrix versions of the smaller expert mixes (IQ4_XS, Q2_K on some layers), judged by KL
  first and then by ear.
