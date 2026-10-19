# drama3-local-streaming

Running the [Fish Audio Drama 3](https://www.marktechpost.com/2026/10/14/fish-audio-drama-3-open-weight-tts-model/) speech model locally on a consumer PC with an 8 GB GPU, by keeping what fits in VRAM and RAM and streaming the rest of the model's experts from an NVMe SSD.

The target use is offline narration: script in, audio file out. Generation speed barely matters (a few hours per video overnight is fine), so we trade speed for memory.

## Why it's possible

- Drama 3 is a mixture-of-experts model: about 35B parameters, 256 routed experts plus 1 shared per layer, 8 picked per step, about 3B active per step.
- Each step produces one codec frame (about 21.5 per second of audio), so a 25-minute narration is about 32,000 steps whatever the hardware.
- Only the active experts are needed per step, so the full model doesn't have to sit in VRAM or even RAM.

## Target hardware

- NVIDIA RTX 4060 Ti 8 GB (Ada, SM89)
- 32 GB RAM, Windows with WSL2
- Crucial P3 NVMe SSD (about 1 to 1.8 GB/s measured)

## Built on

- [speech.cpp](https://github.com/nyosegawa/speech.cpp) (ggml-based, v0.8.10), built with CUDA for SM89 inside WSL
- GGUF quantisations of Drama 3 (IQ3_S 18 GB, Q4_K about 21 GB, Q8_0 38.5 GB)

This repo holds notes, scripts and measurements only. It does not include the model weights or the speech.cpp source; get those from their own projects.

## Plan

1. **Baseline.** Run speech.cpp with Q4_K on a short narration (a 137-word, about 55 s cold open). Measure seconds per step, peak RAM and VRAM, and SSD read rate. Then squeeze RAM (WSL capped at 28 GB, swap off) to see whether the loader already streams from the SSD.
2. **Expert usage logging.** Record which experts each step picks, per layer, over a long passage, to see how skewed routing is.
3. **Tiered cache.** Hottest experts in VRAM, warm ones in RAM, cold ones fetched from the SSD with async prefetch.
4. **Batch paragraphs.** Generate several independent paragraphs together so each expert read serves all of them.
5. **Quality check.** Compare IQ3_S, Q4_K and Q8_0 by blind listening and ASR word error rate.

## Success criteria

- A 25-minute narration renders unattended overnight (under about 6 hours).
- It uses a higher-quality file than RAM alone allows (Q4_K or Q8_0).
- No dropped or repeated words in final takes: an ASR pass flags them for retakes.

## Licence note

Drama 3 is under the Fish Audio Community License v1.0: free commercial use under US$500k annual revenue, products must show "Built with Fish Audio", no cloning a real voice without consent, and serving it as a third-party API needs a separate licence.
