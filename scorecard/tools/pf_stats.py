import json, os, re
R = os.path.expanduser("~/drama3/scorecard-runs")
print("| cap | mode | RTFx | s/frame | major faults | read GB | mean read MB/s |")
print("|---|---|---|---|---|---|---|")
for cap in ["12", "10", "8"]:
    for mode in ["none", "same", "next"]:
        d = f"{R}/pf-{mode}-cap{cap}"
        if not os.path.exists(f"{d}/gen.jsonl"):
            print(f"| {cap} | {mode} | missing |"); continue
        g = [json.loads(l) for l in open(f"{d}/gen.jsonl")]
        t = open(f"{d}/time.txt").read() if os.path.exists(f"{d}/time.txt") else ""
        mf = re.search(r"Major .*: (\d+)", t)
        bi = [int(l.split()[8]) / 1024 for l in open(f"{d}/vmstat.txt").read().splitlines()[2:] if len(l.split()) >= 17 and l.split()[8].isdigit()]
        a = sum(r["audio_s"] for r in g); s = sum(r["request_s"] for r in g)
        print(f"| {cap} GB | {mode} | {a/s:.3f} | {s/(a/(2048/44100)):.3f} | {int(mf.group(1))/1e6:.2f} M | {sum(bi)/1024:.1f} | {sum(bi)/max(len(bi),1):.0f} |")
