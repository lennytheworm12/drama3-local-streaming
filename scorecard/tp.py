"""Throughput of a worker serving several requests at once (SPEECH_STREAMS): submits every take up front, collects the
interleaved replies by id, and reports audio seconds per wall second over the whole batch.

    python tp.py TAG --binary B --model M [--streams 2] [--seeds 1,2] [--only s01,...] [--out DIR]

Writes each take as <id>-s<seed>.wav and a summary line to OUT/TAG/tp.json. Uses worker.py's process handling; the
reply loop here is its own, since replies of several ids interleave.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from worker import Worker, read_jsonl  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def vram_used_mib():
    """The GPU's memory in use, whoever holds it, or None without nvidia-smi."""
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout
        return int(out.split()[0])
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--binary", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--streams", type=int, default=1)
    ap.add_argument("--threads", type=int, help="CPU threads of each stream")
    ap.add_argument("--seeds", default="1,2")
    ap.add_argument("--only", default="s01,s02,s03,s04,s06,s07,s10,s11,s14,s19")
    ap.add_argument("--corpus", default=os.path.join(HERE, "corpus.jsonl"))
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    os.environ["SPEECH_STREAMS"] = str(a.streams)
    out = os.path.join(a.out, a.tag)
    os.makedirs(out, exist_ok=True)
    keep = set(a.only.split(","))
    texts = {c["id"]: c["text"] for c in read_jsonl(a.corpus) if c["id"] in keep}
    jobs = [(i, int(s)) for i in sorted(texts) for s in a.seeds.split(",")]

    vram_before = vram_used_mib()
    w = Worker(a.binary, a.model, ["--threads", str(a.threads)] if a.threads else [], stderr_path=os.path.join(out, "worker.stderr.log"))
    sr = w.ready["model"].get("sample_rate", 44100)
    vram_ready = vram_used_mib()
    pcm = {f"{i}-s{s}": [] for i, s in jobs}
    t0 = time.monotonic()
    for i, s in jobs:
        w._send({"type": "synthesize", "id": f"{i}-s{s}", "text": texts[i], "voice": "none", "seed": s})
    done, stops, vram_peak = 0, {}, vram_ready or 0
    while done < len(jobs):
        msg = w._next(900)
        if msg["type"] == "end":
            vram_peak = max(vram_peak, vram_used_mib() or 0)
        rid = msg.get("id")
        if msg["type"] == "chunk":
            pcm[rid].append(base64.b64decode(msg["pcm"]))
        elif msg["type"] in ("end", "error", "cancelled"):
            stops[rid] = msg.get("stop", msg["type"])
            done += 1
    wall = time.monotonic() - t0
    w.close()
    audio = 0.0
    for rid, parts in pcm.items():
        data = b"".join(parts)
        audio += len(data) / 2 / sr
        with wave.open(os.path.join(out, rid + ".wav"), "wb") as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(data)
    res = {"tag": a.tag, "streams": a.streams, "takes": len(jobs), "audio_s": round(audio, 1), "wall_s": round(wall, 1),
           "throughput_rtfx": round(audio / wall, 3), "load_s": round(w.load_s, 1),
           "not_complete": sum(1 for v in stops.values() if v != "complete"),
           "vram_idle_mib": vram_before, "vram_ready_mib": vram_ready, "vram_peak_mib": vram_peak}
    json.dump(res, open(os.path.join(out, "tp.json"), "w"), indent=2)
    print(json.dumps(res))


if __name__ == "__main__":
    main()
