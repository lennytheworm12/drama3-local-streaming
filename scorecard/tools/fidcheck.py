import sys, struct, array, math
sys.path.insert(0, "/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard")
from fidelity import read, kl
for p in sys.argv[1:]:
    d = read(p)
    steps = sorted({k[0] for k in d}); heads = sorted({k[1] for k in d})
    print(p.split("/")[-1], "records", len(d), "steps", steps[0], "..", steps[-1], "n", len(steps), "heads", heads[:3], "..", heads[-1])
a, b = read(sys.argv[1]), read(sys.argv[2])
row = []
for s in range(0, 12):
    if (s, 0) in a and (s, 0) in b:
        row.append(f"{s}:{kl(a[(s,0)], b[(s,0)]):.3f}")
print("main-head KL by step (first 12):", " ".join(row))
