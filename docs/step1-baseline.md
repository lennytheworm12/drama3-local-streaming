# Drama 3 SSD-streaming experiment — Step 1 results

Date: 2026-10-19. Host: Windows 11, WSL2 Ubuntu 22.04.3 (kernel 6.6.87.2), Ryzen 7 5700 (8C/16T),
32 GB RAM, RTX 4060 Ti 8 GB (driver 610.88), Crucial P3 2 TB NVMe.

## Summary

- speech.cpp **does not mmap** the GGUF. It reads all of it into allocated buffers, so the
  experts it keeps on the CPU live in about 15.5 GB of anonymous RAM. Nothing streams from the
  SSD during generation; disk reads are about 0 MB/s once the model is loaded.
- On this 8 GB card, Drama 3 Q4_K keeps the experts of 4 of its 40 layers on the GPU and
  computes the other 36 on the CPU. Speed is **about 0.4× realtime** (0.10–0.13 s of compute per
  46 ms audio frame), and the model takes 2–6 minutes to load before every run.
- **The 16 GB squeeze run was OOM-killed during the model load** after 40 s. It neither crawled
  nor fell back to the SSD. With this build, the model needs about 16 GB of RAM inside WSL, plus headroom.
- Only seed 1 of 3 finished normally. Seeds 2 and 3 each had a chunk that ran to the 47.6 s
  per-chunk cap: seed 2 contains about 38 s of dead air, and seed 3 has long quiet stretches that may be
  murmuring. Listen before drawing conclusions about quality.

## SSD

Crucial P3 2 TB (CT2000P3PSSD8): NVMe, QLC, no DRAM cache. fio random read, 20 GB file on WSL ext4
(vhdx), direct=1, libaio, 30 s per test; file deleted afterwards.

| Block size | iodepth | MB/s | mean latency |
|---|---|---|---|
| 4 MiB | 1 | 969 | 4.1 ms |
| 4 MiB | 8 | 1802 | 18.4 ms |
| 16 MiB | 1 | 729 | 22.4 ms |
| 16 MiB | 8 | 1153 | 115.7 ms |

## Build

- speech.cpp **v0.8.10** (tag), cloned at `~/drama3/speech.cpp`, submodules initialised.
- CUDA toolkit **13.3** from NVIDIA's `wsl-ubuntu` repo (no Linux driver; `libcuda` comes from
  `/usr/lib/wsl/lib`). cmake from pip.
- `cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release`. Bi ran the
  toolkit install and build by hand in a WSL terminal, because Claude Code's auto-mode classifier
  refused them. `build/speech` links libcudart/libcublas 13. `speech devices` lists
  `CUDA0 RTX 4060 Ti, 8.6 GB, 7.4 GB free`.
- The upstream docs say: "CUDA builds, but is not checked or released"; Vulkan is the tested backend.
- Model: `~/models/Drama-35B-A3B-v3-Q4_K.gguf`, 20,787,264,352 bytes (matches the HF listing).
- Before the runs, ComfyUI (which held about 6.5 GB of VRAM) was closed. Baseline VRAM use was about 0.5 GB (desktop).

## Method

`~/drama3/run.sh TAG SEED` (copy of the scratch script): `speech tts MODEL --voice none --seed N -v`
with the whole narration (`narration.txt`, from `.research/first-scene/`, newlines joined into
one text) under `/usr/bin/time -v`. Alongside it, the script records nvidia-smi memory every 1 s,
vmstat 1 (`bi` = block reads), /proc/PID/status RSS every 1 s, and `smaps_rollup` at 120 s.
Frames = audio seconds / (2048/44100 s). Page cache was not dropped between runs (no passwordless
sudo). WSL memory=28GB, swap=0 for the normal runs. Default thread count (CPU use was 360–450%,
so about 4 cores busy).

## Normal runs (WSL 28 GB)

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Finished | complete | hit max_seconds | hit max_seconds |
| Audio | 40.8 s | 107.5 s (≈38 s silent) | 142.7 s |
| Frames (est.) | 878 | 2314 | 3072 |
| Generation time | 110.2 s | 271.5 s | 320.3 s |
| Seconds per frame | 0.126 | 0.117 | 0.104 |
| Realtime factor (RTFx) | 0.4 | 0.4 | 0.4 |
| Time to first audio | 16.0 s | 18.3 s | 24.5 s |
| Model load | 128.7 s | 160.2 s | 358.1 s |
| Wall clock | 4:03 | 7:20 | 11:28 |
| Peak RSS | 15.97 GB | 16.00 GB | 16.00 GB |
| Peak VRAM (whole GPU) | 7278 MiB | 7281 MiB | 7284 MiB |
| Disk read, total | 20.9 GB | 20.9 GB | 20.6 GB |
| Disk read during generation | 0.2 MB/s mean, 4.4 max | ≈0 (2.4 max) | ≈0 (2.4 max) |
| Peak disk read (load) | 765 MB/s | 458 MB/s | 311 MB/s |

Load read rates averaged only 60–160 MB/s, far below fio, so loading is not limited by the
disk. Seed 3's 6-minute load is unexplained. A likely cause is page-cache pressure: 16 GB of
anonymous memory plus a 20.8 GB file in a 28 GB VM.

WAVs: `normal-seed1.wav`, `normal-seed2.wav`, `normal-seed3.wav` in this folder.

Loudness map (1 char = 1 s; `#` speech, `o` quiet, `.` near-silence):

```
seed1 #################################o######
seed2 ###o.#.o##.....................................#o...........
      ...................................##o##o##o...
seed3 ###oo###.....oooooooooooooooo###################o.oooooooo##
      #####o#############o########ooo######.oooooooooooooooooooooo
      oooooooooooooooooooooo
```

## mmap

- The source does not use mmap (`src/common/model-file.cpp`). It calls `ggml_backend_alloc_ctx_tensors()` per
  backend, then `fseeko` + `fread` of each tensor into those buffers.
- At 120 s into seed 1, `smaps_rollup` showed Rss 16.23 GB, of which **Pss_Anon 16.06 GB** and
  Pss_File 0.08 GB (Private_Dirty 16.14 GB). The weights are private anonymous memory, not
  page-cache-backed file pages. RSS (16.0 GB) is about 77% of the 20.8 GB file, and the rest is on the GPU.
- Consequence: the kernel cannot evict the CPU-side experts and re-read them from the SSD.
  Streaming from the SSD would need an mmap-based loader (or similar) in speech.cpp; it's not a
  configuration option.

## Squeeze test (WSL memory=16GB, swap=0, seed 1)

**OOM-killed during load at 40 s** (exit 137):

```
Out of memory: Killed process 1290 (speech) total-vm:50857392kB, anon-rss:15468672kB, file-rss:512kB, shmem-rss:75776kB
```

VRAM had reached 4.9 GB and about 18.8 GB had been read from disk. The run produced no audio, did not
crawl, and did not fall back to the SSD.

## Problems / notes

- Claude Code's auto mode refused the WSL restart, the git clone, the CUDA toolkit install and the
  attempt to stop ComfyUI. Bi did those steps by hand, or they succeeded after Bi changed permissions.
- Restarting WSL stops ollama, the Hermes gateway and the headless Chromium (they started again when WSL came back up).
- `.wslconfig` has been restored to the original (`memory=12GB`, `swap=4GB`). The backup is kept at
  `%UserProfile%\.wslconfig.bak-drama3`. **Drama 3 cannot run under the original 12 GB cap**; it
  needs memory=28GB (or at least about 20GB) again for any further runs.
- Ideas for follow-up, not tried: `--threads 16` (only about 4 cores were busy); keeping one
  `speech worker`/`serve` process loaded to avoid the 2–6 minute load per run; passing the text one
  sentence per line, or a lower `--max-seconds`, to stop runaway chunks; a voice file for a consistent
  voice; the license (Fish Audio Community License 1.0: commercial OK under $500k/yr revenue).
- Files left in WSL: `~/drama3/` (source, build, runs), `~/models/` (20.8 GB GGUF), CUDA
  toolkit, NVIDIA apt repo key, fio/sysstat/cmake.
