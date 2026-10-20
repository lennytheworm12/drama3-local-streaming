"""Stage 1: synthesize the corpus with one loaded Drama 3 worker.

Output (in OUT/TAG/): <id>-s<seed>.wav per take, gen.jsonl (one record per take),
config.json (what was run, load time, peak memory). Resumable: takes already in
gen.jsonl are skipped.
"""
import argparse
import json
import os
import subprocess
import time
import wave

from worker import Sampler, Worker, append_jsonl, gpu_used_mib, read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")


def parse_opt(s):
    k, _, v = s.partition("=")
    for conv in (int, float):
        try:
            return k, conv(v)
        except ValueError:
            pass
    return k, {"true": True, "false": False}.get(v, v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--seeds", default="1,2,3")
    ap.add_argument("--threads", type=int)
    ap.add_argument("--opt", action="append", default=[], help="request option k=v, repeatable")
    ap.add_argument("--only", help="comma-separated corpus ids")
    ap.add_argument("--add-voice", action="append", default=[], help="NAME=FILE voice file for the worker, repeatable")
    ap.add_argument("--corpus", default=os.path.join(HERE, "corpus.jsonl"))
    ap.add_argument("--binary", default=f"{HOME}/drama3/speech.cpp/build/speech")
    ap.add_argument("--model", default=f"{HOME}/models/Drama-35B-A3B-v3-Q4_K.gguf")
    ap.add_argument("--out", default=f"{HOME}/drama3/scorecard-runs")
    a = ap.parse_args()

    out = os.path.join(a.out, a.tag)
    os.makedirs(out, exist_ok=True)
    manifest = os.path.join(out, "gen.jsonl")
    done = {(r["id"], r["seed"]) for r in read_jsonl(manifest)} if os.path.exists(manifest) else set()
    corpus = read_jsonl(a.corpus)
    if a.only:
        keep = set(a.only.split(","))
        corpus = [c for c in corpus if c["id"] in keep]
    seeds = [int(s) for s in a.seeds.split(",")]
    opts = dict(parse_opt(o) for o in a.opt)
    opts.setdefault("voice", "none")

    args = []
    if a.threads:
        args += ["--threads", str(a.threads)]
    for v in a.add_voice:
        args += ["--add-voice", v]
    rev = subprocess.run(["git", "-C", os.path.dirname(os.path.dirname(a.binary)), "describe", "--tags", "--always"],
                         capture_output=True, text=True).stdout.strip()
    vram0 = gpu_used_mib()
    w = Worker(a.binary, a.model, args, stderr_path=os.path.join(out, "worker.stderr.log"))
    sampler = Sampler(w.pid)
    sr = w.ready["model"].get("sample_rate", 44100)
    print(f"ready in {w.load_s:.1f} s, sr={sr}, threads={w.ready['model'].get('threads')}", flush=True)
    try:
        for c in corpus:
            for seed in seeds:
                if (c["id"], seed) in done:
                    continue
                rid = f"{c['id']}-s{seed}"
                pcm, end, first_s, total_s = w.synthesize(rid, c["text"], seed=seed, **opts)
                wav = os.path.join(out, rid + ".wav")
                with wave.open(wav, "wb") as f:
                    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(pcm)
                audio_s = end["samples"] / sr
                rec = {"id": c["id"], "seed": seed, "text": c["text"], "wav": rid + ".wav",
                       "sample_rate": sr, "audio_s": round(audio_s, 3), "stop": end["stop"],
                       "first_audio_s": round(first_s, 3) if first_s is not None else None,
                       "request_s": round(total_s, 3),
                       "rtfx": round(audio_s / total_s, 3) if total_s else None}
                append_jsonl(manifest, rec)
                print(f"{rid}: {audio_s:.1f} s audio in {total_s:.1f} s, stop={end['stop']}", flush=True)
    finally:
        peak = sampler.stop()
        w.close()
        cfg = {"tag": a.tag, "time_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "binary": a.binary, "speech_cpp_rev": rev, "model": a.model, "worker_args": args,
               "options": opts, "seeds": seeds, "load_s": round(w.load_s, 1),
               "baseline_vram_mib": vram0, "peak": peak,
               "device": w.ready["model"].get("device"), "threads": w.ready["model"].get("threads")}
        with open(os.path.join(out, "config.json"), "w") as f:
            json.dump(cfg, f, indent=2)


if __name__ == "__main__":
    main()
