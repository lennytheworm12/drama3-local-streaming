# Patches against speech.cpp

Both patches are against [speech.cpp](https://github.com/nyosegawa/speech.cpp) main at `eacabcd` (v0.8.10 plus three
commits). Both were checked with `git apply --check` on a clean checkout of that commit.

| Patch | Applies in | What |
|---|---|---|
| `speech.cpp-exp.diff` | the speech.cpp root | Every experiment: mmap loader, expert prefetch, mixed expert quants, timing, routing logs, hot-expert tiering, fidelity recording. 9 files, about 560 lines added. |
| `ggml-mul-mat-id-skip.diff` | the `ggml` submodule (at `a655cf6`) | The CPU `mul_mat_id` skips an expert id of -1. Only the hot-expert tiering experiment needs it. |

```
git clone https://github.com/nyosegawa/speech.cpp && cd speech.cpp
git checkout eacabcd && git submodule update --init --recursive
git apply ../drama3-local-streaming/patches/speech.cpp-exp.diff
git -C ggml apply ../../drama3-local-streaming/patches/ggml-mul-mat-id-skip.diff
```

Every change is switched by an environment variable and off by default, so the patched build behaves like upstream
until you set one. They are experiments, not upstream-ready code: they read the environment instead of taking flags.

## Switches, by file

| Feature | Switch | Files |
|---|---|---|
| **mmap loader.** Maps the GGUF read-only and points the CPU-placed tensors at the file's own pages, so the OS can drop and re-read them instead of holding a 16 GB anonymous copy. POSIX `mmap` and a Win32 `CreateFileMapping`/`MapViewOfFile` path. Output is bit-identical to the fread loader. | `SPEECH_MMAP=1` | `src/common/model-file.{cpp,h}` |
| Whole-view prefetch on Windows (`PrefetchVirtualMemory` once after mapping, as llama.cpp does). On by default with mmap. | `SPEECH_PREFETCH=0` turns it off | `model-file.cpp` |
| Kernel advice on Linux | `SPEECH_MADVISE=random\|sequential\|willneed` | `model-file.cpp` |
| Load profiling: read and copy seconds per buffer type | `SPEECH_LOAD_TIMING=1` | `model-file.cpp` |
| Read a file whose most common tensor type is not its `general.file_type` (our mixed-expert files) | `SPEECH_MIXED_OK=1` | `model-file.cpp` |
| **Expert prefetch from the router.** A CPU custom op passes the router's picks through and calls `madvise(MADV_WILLNEED)` / `PrefetchVirtualMemory` on the chosen experts' gate/up/down slices before they compute. `same`: the layer's own picks. `next`: also guesses the next layer's picks by running its router on this layer's input. Output is bit-identical. | `SPEECH_PREFETCH_EXPERTS=same\|next` | `src/families/drama3/text-model.{cpp,h}` |
| **Mixed expert quants.** `speech quantize` reads the published F16 file (widened to F32 a tensor at a time) and gives tensors matching a name fragment their own type. The Drama 3 layout accepts IQ4_XS, Q3_K, IQ3_S and Q2_K for matrices. | `SPEECH_QUANT_FROM_F16=1`, `SPEECH_QUANT_RULES="_exps=q2_K"` | `src/common/quantize.cpp`, `src/families/drama3/layout.cpp` |
| Per-step timing of text model, audio decoder and codec | `SPEECH_STEP_TIMING=1` | `src/families/drama3/synthesizer.cpp` |
| Router log: every pick per layer per frame | `SPEECH_EXPERT_LOG=path` | `text-model.cpp` |
| Hot-expert GPU tiering (unstable: some sizes give non-finite logits) | `SPEECH_HOT_EXPERTS=list SPEECH_HOT_GB=n` | `text-model.cpp`, `src/engines/drama3-engine.cpp`, ggml patch |
| Threadpool polling | `SPEECH_POLL=0..100` | `drama3-engine.cpp` |
| Teacher-forced fidelity: record a trajectory, replay it on another build, dump logits | `SPEECH_RECORD`, `SPEECH_FORCE`, `SPEECH_LOGITS=path` | `synthesizer.cpp` |

Making a Q2_K-experts file from the published F16:

```
SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_RULES="_exps=q2_K" speech quantize Drama-35B-A3B-v3-F16.gguf Drama-exps-q2k.gguf --type q4_k
SPEECH_MMAP=1 SPEECH_MIXED_OK=1 speech tts Drama-exps-q2k.gguf --voice none -o hello.wav "Hello there."
```

Base type Q4_K, routed experts Q2_K, router F32 (the layout requires it). The result is 13.2 GB against 20.8 GB.

The native Windows build needs no source changes beyond these patches; see [`docs/build-windows.md`](../docs/build-windows.md).
