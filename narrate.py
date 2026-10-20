"""Narrate a text file with Drama 3 on the fastest local setup (native Vulkan, mmap loader, Q2_K experts).

    narrate.cmd script.txt [--takes 3] [--voice none | --voice-file me.voice.gguf] [--model PATH] [--out DIR]

Each non-empty line of the text is one segment. Every segment gets --takes takes, each with its own seed. A take
counts as usable when it finished on its own (no runaway to the time cap) and has no pause over 2 s inside it. The
first usable take of each segment goes into narration.wav, with 0.35 s of silence between segments. Every take
is kept in the takes folder, and takes.md lists them, so you can listen and swap in a better one.
Automatic scores cannot hear "AI cadence", so the default pick is only a starting point.
"""
import argparse
import array
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
    ap.add_argument("--voice", default="none", help="'none', or the name given with --voice-file")
    ap.add_argument("--voice-file", help="a voice file (.voice.gguf) made with `speech voice`")
    ap.add_argument("--model", default=os.path.join(HERE, "win", "Drama-exps-q2k.gguf"))
    ap.add_argument("--binary", default=os.path.join(HERE, "src", "speech.cpp-exp", "build-vk", "speech.exe"))
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

    os.environ.setdefault("SPEECH_MMAP", "1")
    os.environ.setdefault("SPEECH_MIXED_OK", "1")
    args, voice = [], a.voice
    if a.voice_file:
        args += ["--add-voice", f"narrator={a.voice_file}"]
        voice = "narrator"
    t0 = time.monotonic()
    w = Worker(a.binary, a.model, args, stderr_path=os.path.join(out, "worker.log"))
    sr = w.ready["model"].get("sample_rate", 44100)
    print(f"model ready in {w.load_s:.0f} s; {len(segments)} segments x {a.takes} takes", flush=True)

    manifest, chosen_pcm = [], []
    try:
        for i, text in enumerate(segments, 1):
            takes = []
            for k in range(a.takes):
                seed = a.first_seed + k
                pcm, end, _, secs = w.synthesize(f"{i}-{seed}", text, voice=voice, seed=seed)
                name = f"seg{i:03d}-seed{seed}.wav"
                path = os.path.join(out, "takes", name)
                with wave.open(path, "wb") as f:
                    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(pcm)
                st = audio_stats(path)
                ok = end["stop"] == "complete" and st["longest_pause_s"] <= 2.0
                takes.append({"file": name, "seed": seed, "stop": end["stop"], "seconds": round(end["samples"] / sr, 2),
                              "longest_pause_s": st["longest_pause_s"], "usable": ok, "pcm": pcm})
                print(f"  {i}/{len(segments)} seed {seed}: {takes[-1]['seconds']} s {'ok' if ok else 'flagged'} ({secs:.0f} s)", flush=True)
            pick = next((t for t in takes if t["usable"]), takes[0])
            chosen_pcm.append(pick["pcm"])
            manifest.append({"segment": i, "text": text, "chosen": pick["file"],
                             "takes": [{k: v for k, v in t.items() if k != "pcm"} for t in takes]})
    finally:
        w.close()

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
