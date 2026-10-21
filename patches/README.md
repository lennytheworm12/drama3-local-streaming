# Patches against speech.cpp

Both patches are against [speech.cpp](https://github.com/nyosegawa/speech.cpp) main at `eacabcd` (v0.8.10 plus three
commits). Both were checked with `git apply` on a clean export of that commit, and the result matches the tree our
Windows build is made from file for file.

| Patch | Applies in | What |
|---|---|---|
| `speech.cpp-exp.diff` | the speech.cpp root | Every experiment: loaders, expert prefetch, mixed expert quants, the fused audio decoder, concurrent streams, the VRAM savings, flash attention, GPU-layer caps, pinned handoff memory, importance-matrix collection and quantising, hot-expert sidecars, SSD expert streaming, and the measurement switches. 21 files (including the new `src/common/imatrix.{cpp,h}`, `src/families/drama3/expert-stream.{cpp,h}` and `tools/hotx`), about 2,300 lines added. |
| `ggml-experiments.diff` | the `ggml` submodule (at `a655cf6`) | Scheduler timing, split dumps and the rejected early-submit experiment (`ggml-backend.cpp`), and the CPU `mul_mat_id` skipping an expert id of -1 (`ggml-cpu.c`), which the hot-expert sidecar (`SPEECH_HOT_FILE`) and GPU tiering need. |

```
git clone https://github.com/nyosegawa/speech.cpp && cd speech.cpp
git checkout eacabcd && git submodule update --init --recursive
git apply ../drama3-local-streaming/patches/speech.cpp-exp.diff
git -C ggml apply ../../drama3-local-streaming/patches/ggml-experiments.diff
```

Every change is switched by an environment variable and off by default, so the patched build behaves like upstream
until you set one. They are experiments, not upstream-ready code: they read the environment instead of taking flags.

## What we run

[`narrate.py`](../narrate.py) sets these for the best setup (the English-imatrix mixed file, native Vulkan, 4 takes at once):

```
SPEECH_FUSED_DECODER=1 SPEECH_KV_F16=1 SPEECH_MAX_PROMPT_ROWS=2048 SPEECH_MAX_FRAMES=1024
SPEECH_EMBD_ON_CPU=1 SPEECH_FLASH_ATTN=1 SPEECH_SCHED_PINNED=1
SPEECH_STREAMS=4 SPEECH_GPU_EXPERT_LAYERS_EXACT=0   (and --threads 2)
```

For a single take, `SPEECH_STREAMS=1 SPEECH_GPU_EXPERT_LAYERS_EXACT=8` is fastest (0.77×) when nothing else holds VRAM,
and 6 leaves headroom. `SPEECH_MIXED_OK=1` is needed to read the mixed-expert files.

## Switches

**Adopted**

| Switch | What | Files |
|---|---|---|
| `SPEECH_MMAP=1` | mmap loader: maps the GGUF read-only and points CPU-placed tensors at the file's pages (POSIX `mmap`; Win32 `CreateFileMapping`/`MapViewOfFile`). Bit-identical output. Best under a RAM cap; under VRAM and memory pressure on Windows, fread holds up better, so narrate.py now uses fread. | `src/common/model-file.{cpp,h}` |
| `SPEECH_PREFETCH=0` | turns off the whole-view `PrefetchVirtualMemory` on Windows (on by default with mmap) | `model-file.cpp` |
| `SPEECH_PREFETCH_EXPERTS=same\|next` | router-driven prefetch: a CPU custom op asks the OS to read the chosen experts' slices before they compute. `next` also guesses the next layer's picks. | `src/families/drama3/text-model.{cpp,h}` |
| `SPEECH_QUANT_FROM_F16=1`, `SPEECH_QUANT_RULES="_exps=q2_K"`, `SPEECH_MIXED_OK=1` | mixed expert quants: `speech quantize` from the published F16, a type per tensor-name fragment; the layout accepts IQ4_XS, Q3_K, IQ3_S and Q2_K | `src/common/quantize.cpp`, `src/families/drama3/layout.cpp`, `model-file.cpp` |
| `SPEECH_FUSED_DECODER=1` | the audio decoder's 9 codebook graphs in one, sampling on the GPU (top-k by argsort, cumsum, one-hot embedding mix). Bit-identical takes. | `src/families/drama3/audio-decoder.{cpp,h}`, `synthesizer.cpp` |
| `SPEECH_STREAMS=n` | n synthesizers over one copy of the weights, each with its own device and CPU backend, so n requests run at once; the API lock is relaxed for it and the worker serves n requests side by side | `src/engines/drama3-engine.cpp`, `src/engines/engine.h`, `src/api/request.cpp`, `tools/worker/worker.cpp` |
| `SPEECH_KV_F16=1` | keys and values cached in half precision (KL against F32 0.001–0.003) | `drama3-engine.cpp`, `src/families/drama3/attention.cpp` |
| `SPEECH_MAX_PROMPT_ROWS=n`, `SPEECH_MAX_FRAMES=n` | caches and graph buffers sized for a line (2,048 + 1,024) instead of 8,192 + 2,048 rows; longer prompts are refused | `src/families/drama3/synthesizer.cpp` |
| `SPEECH_EMBD_ON_CPU=1` | the 0.3 GB `token_embd` in RAM, its row decoded on the CPU each frame | `drama3-engine.cpp`, `text-model.cpp` |
| `SPEECH_FLASH_ATTN=1` | `ggml_flash_attn_ext` with the F16 cache, F32 accumulation (−5.5 ms a frame) | `attention.cpp` |
| `SPEECH_SCHED_PINNED=1` | the scheduler's CPU buffers in Vulkan pinned host memory, so GPU↔CPU handoff copies are faster (bit-identical, −3 ms a frame) | `text-model.cpp` |
| `SPEECH_IMATRIX_OUT=path`, `SPEECH_QUANT_IMATRIX=path` | importance matrix: an eval callback on every MUL_MAT / MUL_MAT_ID of the text model, audio decoder and head accumulates each input channel's sum of squares (per expert for stacked experts) and saves it at exit; `speech quantize` then weights each matrix's rounding error by it | `src/common/imatrix.{cpp,h}`, `src/common/graph.cpp`, `text-model.cpp`, `quantize.cpp`, `CMakeLists.txt` |
| `SPEECH_HOT_FILE=path` (opt-in) | a sidecar from `tools/hotx` with each layer's most-routed 30% of experts at Q5_K/Q6_K and the rest at Q4_K, used in place of the main file's CPU experts; picks go to the hot or cold tensor with -1 in the other. `narrate.cmd --hot q6\|q5`. | `drama3-engine.cpp`, `text-model.{cpp,h}`, `tools/hotx/hotx.cpp` |
| `SPEECH_STREAM_MB=n`, `SPEECH_STREAM_IO=overlapped` | SSD streaming: the CPU layers' experts are not loaded; a cache of n MB of whole experts takes their place, filled by unbuffered reads (all of a layer's misses at once with `overlapped`). Bit-identical takes. `narrate.cmd --ram-gb N`. | `src/families/drama3/expert-stream.{cpp,h}`, `text-model.cpp`, `drama3-engine.cpp` |
| `SPEECH_GPU_EXPERT_LAYERS=n`, `SPEECH_GPU_EXPERT_LAYERS_EXACT=n` | cap, or set exactly, how many layers' experts go on the GPU. The cap fixes VRAM overcommit when other apps hold VRAM; the exact count is needed because the automatic estimate doesn't see the smaller caches. | `drama3-engine.cpp` |

**Tried and rejected** (kept so the results can be reproduced)

| Switch | What | Files |
|---|---|---|
| `SPEECH_CPU_REPACK=1` | Q4_K experts in ggml's AVX2 interleaved layout | `model-file.{cpp,h}` |
| `SPEECH_DECODER_ON_CPU=1` | the audio decoder on the CPU, to free 1.4 GB of VRAM | `drama3-engine.cpp`, `audio-decoder.h` |
| `SPEECH_ONE_GRAPH=1` | one scheduled graph per frame instead of four | `synthesizer.cpp`, `audio-decoder.h`, `text-model.h` |
| `SPEECH_FUSE_OPS=1` | router in llama.cpp's node order (for Vulkan's topk_moe fusion), swiglu as one node | `text-model.cpp`, `audio-decoder.cpp` |
| `SPEECH_SKIP_CPU_EXPERTS=1` | draft model for speculative decoding: CPU-held layers keep only the shared expert | `text-model.cpp` |
| `SPEECH_HOT_EXPERTS=list SPEECH_HOT_GB=n` | hot-expert GPU tiering (unstable: some sizes give non-finite logits; needs the ggml `mul_mat_id` change) | `text-model.cpp`, `drama3-engine.cpp` |
| `SPEECH_POLL=0..100` | threadpool polling | `drama3-engine.cpp` |
| `SPEECH_STREAM_PIN=f`, `SPEECH_STREAM_IMATRIX=path` | pin a fraction of the stream cache to the calibration's most-routed experts (lost to plain LRU) | `expert-stream.cpp` |
| `SPEECH_STREAM_PREFETCH=1` | read ahead the next layer's guessed picks (always slower) | `expert-stream.cpp`, `text-model.cpp` |
| `SPEECH_STREAM_FILE=path` | a contiguous expert file from `stream_layout.py`, one read per expert (about neutral) | `expert-stream.cpp` |
| `GGML_SCHED_EARLY=1` | shared expert computed on the GPU beside the CPU experts: the device split's tail is submitted once the CPU split has copied its inputs | `text-model.cpp`, ggml `src/ggml-backend.cpp` |

**Measurement**

| Switch | What | Files |
|---|---|---|
| `SPEECH_LOAD_TIMING=1` | read and copy seconds per buffer type | `model-file.cpp` |
| `SPEECH_MADVISE=random\|sequential\|willneed` | kernel advice on the mapping (Linux) | `model-file.cpp` |
| `SPEECH_STEP_TIMING=1`, `SPEECH_DECODER_TIMING=1` | per-frame time of text model, audio decoder and codec | `synthesizer.cpp`, `audio-decoder.cpp` |
| `SPEECH_EXPERT_LOG=path` | every router pick per layer per frame | `text-model.cpp` |
| `SPEECH_RECORD`, `SPEECH_FORCE`, `SPEECH_LOGITS=path` | teacher-forced fidelity: record a trajectory, replay it on another build, dump logits | `synthesizer.cpp` |
| `GGML_SCHED_TIMING=1`, `GGML_SCHED_SPLITS=n` | per-backend copy and compute time per split (synchronised after each split), and the splits of the first n graphs | ggml `src/ggml-backend.cpp` |

## Making the English-imatrix files and a Q2_K-experts file from the published F16

```
SPEECH_IMATRIX_OUT=imatrix-en.simx python scorecard/tools/calib.py --binary speech --model MODEL.gguf --voice-file narrator.voice.gguf
SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_IMATRIX=imatrix-en.simx speech quantize Drama-35B-A3B-v3-F16.gguf Drama-imx-q4k.gguf --type q4_k
SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_IMATRIX=imatrix-en2.simx SPEECH_QUANT_RULES="_exps=q4_K,token_embd=q8_0,output=q8_0,blk.=q6_K,ad.=q6_K" \
  speech quantize Drama-35B-A3B-v3-F16.gguf Drama-imx2-mix.gguf --type q4_k
SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_RULES="_exps=q2_K" speech quantize Drama-35B-A3B-v3-F16.gguf Drama-exps-q2k.gguf --type q4_k
SPEECH_MIXED_OK=1 speech tts Drama-exps-q2k.gguf --voice none -o hello.wav "Hello there."
```

`Drama-imx-q4k.gguf` has the published file's types and size (20.8 GB). `Drama-imx2-mix.gguf`, the default, uses the round 2 matrix (which also covers the audio decoder and head) and keeps everything but the routed experts at Q6_K, with the embedding and head at Q8_0: 21.8 GB. The matrices are about 190 MB each and not in this repo ([`imx_quant.sh`](../scorecard/tools/imx_quant.sh) and [`imx2_quant.sh`](../scorecard/tools/imx2_quant.sh) are the scripts we ran). The Q2_K file has base type Q4_K, routed experts Q2_K and the router F32 (the layout requires it): 13.2 GB against 20.8 GB.

A hot-expert sidecar (the default arguments of [`hotx_run.sh`](../scorecard/tools/hotx_run.sh)):

```
hotx Drama-35B-A3B-v3-F16.gguf imatrix-en2.simx Drama-hot30-q6_K.gguf 0.3 q6_K
```

The native Windows build needs no source changes beyond these patches; see [`docs/build-windows.md`](../docs/build-windows.md).
