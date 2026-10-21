"""Runs English calibration text through one loaded worker, for SPEECH_IMATRIX_OUT to collect an importance matrix.

    python calib.py --binary B --model M [--voice-file V] [--limit N]

Texts: the LibriSpeech subset and the English scorecard sentences, without the two fidelity sentences, which the
importance matrix is later judged on. Each text runs once with the model's own voice, and, with --voice-file, once
more with that voice. The worker saves the matrix when it exits.
"""
import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from worker import Worker, read_jsonl  # noqa: E402

HELD_OUT = ("astronauts", "zippers")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--voice-file")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--log", default=os.devnull)
    a = ap.parse_args()
    sc = os.path.dirname(HERE)
    texts = [c["text"] for name in ("corpus-librispeech-100.jsonl", "corpus.jsonl")
             for c in read_jsonl(os.path.join(sc, name)) if not any(h in c["text"] for h in HELD_OUT)]
    if a.limit:
        texts = texts[:a.limit]
    args = ["--add-voice", f"narrator={a.voice_file}"] if a.voice_file else []
    voices = ["none"] + (["narrator"] if a.voice_file else [])
    w = Worker(a.binary, a.model, args, stderr_path=a.log)
    t0 = time.monotonic()
    done = 0
    try:
        for v in voices:
            for i, text in enumerate(texts):
                w.synthesize(f"{v}-{i}", text, voice=v, seed=1 + i)
                done += 1
                if done % 10 == 0:
                    print(f"{done}/{len(texts) * len(voices)} in {time.monotonic() - t0:.0f} s", flush=True)
    finally:
        w.close(timeout_s=300)
    print(f"done: {done} texts in {time.monotonic() - t0:.0f} s")


if __name__ == "__main__":
    main()
