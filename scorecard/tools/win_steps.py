import os, re, sys
R = r"C:\Users\bphan\PersonalProjects\drama3-local\win\runs"
for t in sys.argv[1:]:
    log = open(os.path.join(R, t, "worker.stderr.log"), errors="replace").read()
    rows = [list(map(float, x)) for x in re.findall(r"(\d+) frames, per frame ms: text model ([\d.]+), head\+sample ([\d.]+), audio decoder ([\d.]+), codec ([\d.]+)", log)][1:]
    n = sum(r[0] for r in rows)
    w = [sum(r[0] * r[i] for r in rows) / n for i in range(1, 5)]
    print(f"{t}: frames={int(n)} text={w[0]:.1f} head={w[1]:.1f} decoder={w[2]:.1f} codec={w[3]:.1f} sum={sum(w):.1f} ms")
