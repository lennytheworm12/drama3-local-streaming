# Building the patched speech.cpp natively on Windows (Vulkan)

Native Windows with Vulkan was the fastest setup we measured: 0.63× realtime for the stock release against 0.44× for
CUDA inside WSL2, and 0.70× with the patches and Q2_K experts. The gap is cheaper GPU↔CPU synchronisation outside WSL's
GPU paravirtualisation, which matters because each CPU-computed layer costs about 1.1 ms of handoff per frame.

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
rem Optional, only for the hot-expert tiering experiment:
git -C ggml apply ..\..\drama3-local-streaming\patches\ggml-mul-mat-id-skip.diff
```

Then, from a plain `cmd`:

```
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set VULKAN_SDK=C:\VulkanSDK\1.4.363.0
set PATH=%VULKAN_SDK%\Bin;%PATH%
cmake -B build-vk -G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vk --config Release -j 12
```

`build-vk\speech.exe` is the result. [`scorecard/tools/build_win.cmd`](../scorecard/tools/build_win.cmd) is the same
thing as a script, with the paths of our rig (edit the `cd` line for yours).

## Running

```
wsl --shutdown
set SPEECH_MMAP=1
set SPEECH_MIXED_OK=1
build-vk\speech.exe tts Drama-exps-q2k.gguf --voice none -o hello.wav "Hello there."
```

Shut WSL down first if it is running: its VM holds RAM the model wants. With Q2_K experts the model needs about 8 GB.
`SPEECH_PREFETCH_EXPERTS=same` adds router-driven prefetch, which matters when RAM cannot hold the working set.

[`narrate.cmd`](../narrate.cmd) wraps all of this for a text file: one segment per line, several takes per segment,
and a stitched `narration.wav` of the first usable take of each.

## Notes from getting it working

- The first Win32 mmap path opened the file with `FILE_FLAG_RANDOM_ACCESS`. That turns off the cache manager's
  read-ahead, so every page was a soft fault, and mmap ran 26% slower than fread (0.465× against 0.629×). Dropping
  the flag and calling `PrefetchVirtualMemory` on the whole view made mmap faster than fread with a quicker start
  (0.654×, ready in 15 s).
- The Vulkan backend fits one more expert layer on the 8 GB card than CUDA does (5 against 4 at Q4_K, 9 at Q2_K).
