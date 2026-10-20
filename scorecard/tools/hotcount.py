import collections, sys
lines = [tuple(map(int, l.split())) for l in open(sys.argv[1])]
mb = 1.75 / 1024
for gb in (1.0, 1.7, 2.2):
    n = int(gb / mb)
    c = collections.Counter(l for l, _ in lines[:n])
    print(gb, "GB:", n, "experts; per-layer counts:", [c.get(l, 0) for l in range(40)])
