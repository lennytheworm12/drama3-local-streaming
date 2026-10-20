import re, sys, os
for d in sys.argv[1:]:
    p = os.path.join(d, "worker.stderr.log")
    rows = []
    for l in open(p, errors="replace"):
        m = re.search(r"(\d+) frames, per frame ms: text model ([\d.]+), head\+sample ([\d.]+), audio decoder ([\d.]+), codec ([\d.]+)", l)
        if m: rows.append([float(x) for x in m.groups()])
    rows = rows[1:]  # drop warmup
    n = sum(r[0] for r in rows)
    if not n: print(os.path.basename(d), "no timing"); continue
    w = [sum(r[i] * r[0] for r in rows) / n for i in range(1, 5)]
    print(f"{os.path.basename(d.rstrip('/'))}: frames={int(n)} text={w[0]:.1f} head={w[1]:.1f} decoder={w[2]:.1f} codec={w[3]:.1f} total={sum(w):.1f} ms/frame")
