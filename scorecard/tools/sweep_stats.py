import json, os, re, glob
R = os.path.expanduser("~/drama3/scorecard-runs")
print("| cap | takes | audio s | gen s | RTFx | s/frame | worker ready s | peak RSS GB (file) | major faults | disk read GB | mean read MB/s during run |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for cap in ["none", "20", "16", "12", "10", "8"]:
    d = f"{R}/sweep-cap{cap}"
    g = [json.loads(l) for l in open(f"{d}/gen.jsonl")] if os.path.exists(f"{d}/gen.jsonl") else []
    cfg = json.load(open(f"{d}/config.json")) if os.path.exists(f"{d}/config.json") else {}
    t = open(f"{d}/time.txt").read() if os.path.exists(f"{d}/time.txt") else ""
    mf = re.search(r"Major .*: (\d+)", t)
    bi = []
    for l in open(f"{d}/vmstat.txt").read().splitlines()[2:]:
        f = l.split()
        if len(f) >= 17 and f[8].isdigit(): bi.append(int(f[8]) / 1024)
    a = sum(r["audio_s"] for r in g); s = sum(r["request_s"] for r in g)
    pk = cfg.get("peak", {})
    print(f"| {cap} | {len(g)} | {a:.1f} | {s:.1f} | {a/s if s else 0:.3f} | {s/(a/(2048/44100)) if a else 0:.3f} | {cfg.get('load_s')} | "
          f"{pk.get('rss_kb',0)/1048576:.1f} ({pk.get('file_kb',0)/1048576:.1f}) | {mf.group(1) if mf else '?'} | {sum(bi)/1024:.1f} | {sum(bi)/len(bi) if bi else 0:.0f} |")
