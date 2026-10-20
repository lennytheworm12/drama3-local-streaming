"""Summary of the Windows runs (win\\runs): speed, startup, GPU expert layers, text-model ms/frame, memory."""
import json
import os
import re
import statistics
import sys

R = r"C:\Users\bphan\PersonalProjects\drama3-local\win\runs"
for t in sys.argv[1:]:
    d = os.path.join(R, t)
    if not os.path.exists(os.path.join(d, "gen.jsonl")):
        print(t, "missing")
        continue
    g = [json.loads(l) for l in open(os.path.join(d, "gen.jsonl"))]
    c = json.load(open(os.path.join(d, "config.json")))
    a = sum(r["audio_s"] for r in g)
    s = sum(r["request_s"] for r in g)
    log = open(os.path.join(d, "worker.stderr.log"), errors="replace").read()
    m = re.search(r"experts of (\d+) of its 40 layers", log)
    held = 40 - int(m.group(1)) if m else "?"
    steps = [list(map(float, x)) for x in re.findall(
        r"(\d+) frames, per frame ms: text model ([\d.]+), head\+sample ([\d.]+), audio decoder ([\d.]+), codec ([\d.]+)", log)][1:]
    n = sum(x[0] for x in steps)
    txt = sum(x[0] * x[1] for x in steps) / n if n else float("nan")
    print(f"| {t} | {a / s:.3f} | {statistics.median(r['first_audio_s'] for r in g):.2f} s | {c['load_s']} s | {held} | "
          f"{txt:.1f} | {c['peak']['rss_kb'] / 1048576:.1f} GB | {c['peak']['anon_kb'] / 1048576:.1f} GB | {c['peak']['vram_mib']} MiB |")
