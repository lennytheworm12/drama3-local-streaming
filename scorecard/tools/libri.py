import json, re, sys, tarfile
src, out = sys.argv[1], sys.argv[2]
utts = []
with tarfile.open(src) as tf:
    for m in tf:
        if m.name.endswith(".trans.txt"):
            for line in tf.extractfile(m).read().decode().splitlines():
                uid, text = line.split(" ", 1)
                if 8 <= len(text.split()) <= 25:
                    utts.append((uid, text))
utts.sort()
step = len(utts) / 100
pick = [utts[int(i * step)] for i in range(100)]
def case(t):
    t = t.lower()
    t = re.sub(r"\bi\b", "I", t)
    return t[0].upper() + t[1:] + "."
with open(out, "w") as f:
    for uid, text in pick:
        f.write(json.dumps({"id": "ls-" + uid, "text": case(text)}) + "\n")
print(len(utts), "candidates;", len(pick), "picked; e.g.", case(pick[0][1]))
