"""Narrate a text file with Drama 3 on the fastest local setup (native Vulkan, Q4_K, four takes side by side).

    narrate.cmd script.txt [--takes 3] [--voice none | --voice-file me.voice.gguf] [--model PATH] [--out DIR]

Each non-empty line of the text is one segment. Every segment gets --takes takes, each with its own seed. A take
counts as usable when it finished on its own (no runaway to the time cap) and has no pause over 2 s inside it. The
first usable take of each segment goes into narration.wav, with 0.35 s of silence between segments. Every take
is kept in the takes folder, and takes.md lists them, so you can listen and swap in a better one.
Automatic scores cannot hear "AI cadence", so the default pick is only a starting point.
"""
import argparse
import array
import base64
import json
import os
import sys
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "scorecard"))
from score import audio_stats  # noqa: E402
from worker import Worker  # noqa: E402

GAP_S = 0.35


def main():
    ap = argparse.ArgumentParser(description="Narrate a text file with Drama 3.")
    ap.add_argument("text")
    ap.add_argument("--takes", type=int, default=3)
    ap.add_argument("--first-seed", type=int, default=1)
    ap.add_argument("--streams", type=int, default=4, help="takes generated side by side (4 fastest; 1 if VRAM is tight)")
    # The 30% of each layer's routed experts the English calibration used most at a higher type (2026-10-21), from the
    # sidecars hotx writes: q6 halves the main token's KL from F16 (0.013 against 0.023) for 13% less speed and 2.4 GB
    # more RAM; q5 gives about the same KL for 7% less speed and 1.2 GB more.
    ap.add_argument("--hot", choices=("none", "q5", "q6"), default="none", help="hot experts at a higher type: closer to the full model, slower")
    # SSD streaming (2026-10-21) for a machine with less RAM: the CPU layers' experts read from the SSD into a cache of
    # the RAM given less the 1.8 GB the process takes without them; least recently used, all of a layer's misses read
    # at once, bypassing Windows' file cache. One take at a time: 0.40x at 12 GB, 0.34x at 10, 0.27x at 8 (0.76x in
    # RAM), the same takes as in RAM. Pinning the calibration's hottest experts and reading ahead both measured slower.
    ap.add_argument("--ram-gb", type=float, help="stream the experts from the SSD to fit in this much RAM (one take at a time)")
    ap.add_argument("--voice", default="none", help="'none', or the name given with --voice-file")
    ap.add_argument("--voice-file", help="a voice file (.voice.gguf) made with `speech voice`")
    # Q4_K: in Bi's blind round 2 it was preferred (69% against 44% "would watch"), and Q2_K's takes drew the intonation
    # complaints. The default is our file quantized from F16 with an English importance matrix of the text model, the
    # audio decoder and the head, routed experts Q4_K and everything else Q6_K or Q8_0 (2026-10-21): 1 GB larger and as
    # fast as the published Q4_K, with KL from F16 on 6 held-out sentences of 0.027 against 0.073 for the main token and
    # 0.019 against 0.156 for the codebooks (83% of codebook picks match F16's, against 53%).
    # Pass --model win\Drama-35B-A3B-v3-Q4_K.gguf for the published file, win\Drama-exps-q2k.gguf for faster drafts.
    ap.add_argument("--model", default=os.path.join(HERE, "win", "Drama-imx2-mix.gguf"))
    ap.add_argument("--binary", default=os.path.join(HERE, "src", "speech.cpp-exp", "build-vk3", "speech.exe"))
    ap.add_argument("--out")
    a = ap.parse_args()
    if not 1 <= a.takes <= 20:
        sys.exit("--takes must be between 1 and 20")

    with open(a.text, encoding="utf-8") as f:
        segments = [l.strip() for l in f if l.strip()]
    if not segments:
        sys.exit(f"{a.text} has no text")
    out = a.out or os.path.splitext(a.text)[0] + "-narration"
    os.makedirs(os.path.join(out, "takes"), exist_ok=True)

    # fread, not mmap: under memory pressure Windows trims mapped pages and the CPU experts slow down.
    os.environ.setdefault("SPEECH_MMAP", "0")
    os.environ.setdefault("SPEECH_MIXED_OK", "1")
    # The audio decoder's nine codebook draws in one GPU graph: bit-identical takes, about 3 ms a frame faster.
    os.environ.setdefault("SPEECH_FUSED_DECODER", "1")
    # Device memory (2026-10-20): keys and values in half precision, caches and graph buffers sized for a line's
    # chunk (2,048 prompt rows, 1,024 frames, 47 s) rather than the model's longest, and the 0.3 GB embedding table
    # in RAM. That is 1.6 GB less per stream, which made room for more streams; flash attention saves 5 ms a frame.
    for k, v in {"SPEECH_KV_F16": "1", "SPEECH_MAX_PROMPT_ROWS": "2048", "SPEECH_MAX_FRAMES": "1024",
                 "SPEECH_EMBD_ON_CPU": "1", "SPEECH_FLASH_ATTN": "1",
                 # the CPU's side of each layer's handoff in the device's pinned memory: 5% faster, the same takes
                 "SPEECH_SCHED_PINNED": "1"}.items():
        os.environ.setdefault(k, v)
    # Several takes at once, one's CPU experts beside another's GPU layers: 4 streams of 2 threads gave 1.24-1.27x
    # realtime throughput, 3 streams 1.14-1.20x, 2 streams 1.08x, one stream 0.77x with 8 layers' experts on the GPU.
    # Each stream's caches take device memory, so with several every layer's experts stay with the CPU; a single
    # stream holds 5 layers' (about 6.7 GB with the mixed file; more overcommits the card once other programs take some).
    # Four streams of the mixed file peak at 7.4 GB of the card's 8; with other programs holding VRAM, use --streams 3.
    streams = 1 if a.ram_gb else a.streams
    if a.ram_gb:
        if a.ram_gb < 4:
            sys.exit("--ram-gb needs at least 4: the process takes 1.8 GB besides its expert cache")
        os.environ.setdefault("SPEECH_STREAM_MB", str(int((a.ram_gb - 1.8) * 1024 * 0.98)))
        os.environ.setdefault("SPEECH_STREAM_IO", "overlapped")
    os.environ.setdefault("SPEECH_STREAMS", str(streams))
    if a.hot != "none":
        os.environ.setdefault("SPEECH_HOT_FILE", os.path.join(HERE, "win", f"Drama-hot30-{a.hot}_K.gguf"))
    os.environ.setdefault("SPEECH_GPU_EXPERT_LAYERS_EXACT", "0" if streams > 1 else "5")
    args, voice = [], a.voice
    if streams > 1:
        args += ["--threads", str(max(2, 8 // streams))]
    if a.voice_file:
        args += ["--add-voice", f"narrator={a.voice_file}"]
        voice = "narrator"
    t0 = time.monotonic()
    w = Worker(a.binary, a.model, args, stderr_path=os.path.join(out, "worker.log"))
    sr = w.ready["model"].get("sample_rate", 44100)
    print(f"model ready in {w.load_s:.0f} s; {len(segments)} segments x {a.takes} takes, {streams} at a time", flush=True)

    # Every take is submitted at once; the worker runs `streams` of them side by side and the replies interleave by id.
    results = {}
    try:
        ids = {}
        for i, text in enumerate(segments, 1):
            for k in range(a.takes):
                seed = a.first_seed + k
                rid = f"{i}-{seed}"
                ids[rid] = (i, seed)
                w._send({"type": "synthesize", "id": rid, "text": text, "voice": voice, "seed": seed})
        pcm = {rid: [] for rid in ids}
        while len(results) < len(ids):
            msg = w._next(1800)
            rid = msg.get("id")
            if msg["type"] == "chunk":
                pcm[rid].append(base64.b64decode(msg["pcm"]))
            elif msg["type"] == "end":
                results[rid] = (b"".join(pcm[rid]), msg)
                i, seed = ids[rid]
                print(f"  {i}/{len(segments)} seed {seed}: {msg['samples'] / sr:.1f} s ({len(results)}/{len(ids)})", flush=True)
            elif msg["type"] in ("error", "cancelled"):
                raise RuntimeError(f"take {rid} failed: {msg}")
    finally:
        w.close()

    manifest, chosen_pcm = [], []
    for i, text in enumerate(segments, 1):
        takes = []
        for k in range(a.takes):
            seed = a.first_seed + k
            pcm, end = results[f"{i}-{seed}"]
            name = f"seg{i:03d}-seed{seed}.wav"
            path = os.path.join(out, "takes", name)
            with wave.open(path, "wb") as f:
                f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(pcm)
            st = audio_stats(path)
            ok = end["stop"] == "complete" and st["longest_pause_s"] <= 2.0
            takes.append({"file": name, "seed": seed, "stop": end["stop"], "seconds": round(end["samples"] / sr, 2),
                          "longest_pause_s": st["longest_pause_s"], "usable": ok, "pcm": pcm})
        pick = next((t for t in takes if t["usable"]), takes[0])
        chosen_pcm.append(pick["pcm"])
        manifest.append({"segment": i, "text": text, "chosen": pick["file"],
                         "takes": [{k: v for k, v in t.items() if k != "pcm"} for t in takes]})

    gap = array.array("h", [0] * int(GAP_S * sr)).tobytes()
    with wave.open(os.path.join(out, "narration.wav"), "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr)
        f.writeframes(gap.join(chosen_pcm))
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    lines = ["# Takes", "", "The chosen take is marked ►. Flagged takes ran to the time cap or have a pause over 2 s.", ""]
    for m in manifest:
        lines.append(f"## {m['segment']}. {m['text']}")
        for t in m["takes"]:
            mark = "►" if t["file"] == m["chosen"] else " "
            lines.append(f"- {mark} `takes/{t['file']}`, {t['seconds']} s{'' if t['usable'] else ', flagged'}")
        lines.append("")
    with open(os.path.join(out, "takes.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"done in {time.monotonic() - t0:.0f} s: {os.path.join(out, 'narration.wav')}")


if __name__ == "__main__":
    main()
