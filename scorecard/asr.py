"""Stage 2: transcribe every take in gen.jsonl with Qwen3-ASR (speech.cpp worker).

Output: asr.jsonl in the run folder (id, seed, hyp, stop). Resumable. Run after
gen.py so the TTS model's memory is free.
"""
import argparse
import os
import wave

from worker import Worker, append_jsonl, read_jsonl

HOME = os.path.expanduser("~")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir")
    ap.add_argument("--binary", default=f"{HOME}/drama3/speech.cpp/build/speech")
    ap.add_argument("--model", default="qwen3-asr-1.7b")
    ap.add_argument("--language", default="en", help="the language the ASR is told; 'auto' to let it detect")
    a = ap.parse_args()

    gen = read_jsonl(os.path.join(a.run_dir, "gen.jsonl"))
    out = os.path.join(a.run_dir, "asr.jsonl")
    done = {(r["id"], r["seed"]) for r in read_jsonl(out)} if os.path.exists(out) else set()
    todo = [g for g in gen if (g["id"], g["seed"]) not in done]
    if not todo:
        return
    w = Worker(a.binary, a.model, stderr_path=os.path.join(a.run_dir, "asr.stderr.log"))
    try:
        for g in todo:
            with wave.open(os.path.join(a.run_dir, g["wav"])) as f:
                sr, pcm = f.getframerate(), f.readframes(f.getnframes())
            end = w.transcribe(f"{g['id']}-s{g['seed']}", pcm, sr, language=a.language)
            append_jsonl(out, {"id": g["id"], "seed": g["seed"], "hyp": end["text"], "asr_stop": end["stop"]})
            print(f"{g['id']}-s{g['seed']}: {end['text'][:80]}", flush=True)
    finally:
        w.close()


if __name__ == "__main__":
    main()
