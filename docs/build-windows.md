# Building the patched speech.cpp natively on Windows (Vulkan)

Native Windows with Vulkan was the fastest setup we measured. The stock release runs at 0.63× realtime, against 0.44× for
CUDA inside WSL2, and with our patches one Q4_K take reaches 0.77×, or 1.24–1.27× realtime throughput with four takes at
once. The gap comes from cheaper GPU↔CPU synchronisation outside WSL's GPU paravirtualisation. This matters because each
CPU-computed layer costs about 1.1 ms of handoff per frame.

## Prerequisites

- Visual Studio 2022 Build Tools with the "Desktop development with C++" workload (MSVC, CMake, Ninja)
- [Vulkan SDK](https://vulkan.lunarg.com/sdk/home#windows) 1.4.363.0 (any recent version should do)
- git

## Steps

```
git clone https://github.com/nyosegawa/speech.cpp
cd speech.cpp
git checkout eacabcd
git submodule update --init --recursive
git apply path\to\drama3-local-streaming\patches\speech.cpp-exp.diff
rem Needed for hot experts (--hot) and scheduler timing:
git -C ggml apply ..\..\drama3-local-streaming\patches\ggml-experiments.diff
```

Then, from a plain `cmd`:

```
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set VULKAN_SDK=C:\VulkanSDK\1.4.363.0
set PATH=%VULKAN_SDK%\Bin;%PATH%
cmake -B build-vk -G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vk --config Release -j 12
```

The result is `build-vk\speech.exe`. [`scorecard/tools/build_win3.cmd`](../scorecard/tools/build_win3.cmd) performs the
same steps as a script (building into `build-vk3`) with the paths of our machine, so edit the `cd` line for yours.

## Running

```
wsl --shutdown
set SPEECH_FUSED_DECODER=1
set SPEECH_KV_F16=1
set SPEECH_MAX_PROMPT_ROWS=2048
set SPEECH_MAX_FRAMES=1024
set SPEECH_EMBD_ON_CPU=1
set SPEECH_FLASH_ATTN=1
set SPEECH_GPU_EXPERT_LAYERS_EXACT=6
build-vk\speech.exe tts Drama-35B-A3B-v3-Q4_K.gguf --voice none -o hello.wav "Hello there."
```

If WSL is running, shut it down first, because its VM holds RAM that the model needs. Other GPU apps should also be
closed, or `SPEECH_GPU_EXPERT_LAYERS_EXACT` lowered: if the expert layers overcommit VRAM, Windows pages buffers out and
speed halves. We use 8 layers when nothing else holds VRAM. For several takes at once, run `speech worker` with
`SPEECH_STREAMS=4`, `SPEECH_GPU_EXPERT_LAYERS_EXACT=0` and `--threads 2`, and submit the takes together.
`SPEECH_SCHED_PINNED=1` adds about 5%.

[`narrate.cmd`](../narrate.cmd) wraps all of this for a text file. It treats each line as one segment, generates several
takes per segment four at a time (`--streams 3` with other GPU apps open), and stitches the first usable take of each
into `narration.wav`. `--hot q6` uses a hot-expert sidecar, and `--ram-gb 8` streams the experts from the SSD to fit in
8 GB of RAM.

## Lessons from the port

- Our first Win32 mmap path opened the file with `FILE_FLAG_RANDOM_ACCESS`. That flag turns off the cache manager's
  read-ahead, so every page became a soft fault, and mmap ran 26% slower than fread (0.465× against 0.629×). Dropping
  the flag and calling `PrefetchVirtualMemory` on the whole view made mmap faster than fread, with a quicker start
  (0.654×, ready in 15 s).
- The Vulkan backend fits one more expert layer on the 8 GB card than CUDA does (5 against 4 at Q4_K, 9 at Q2_K).
