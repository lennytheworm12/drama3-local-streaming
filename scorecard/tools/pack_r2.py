import json, os, random, shutil
R = os.path.expanduser("~/drama3/scorecard-runs")
LOCAL = "/mnt/c/Users/bphan/PersonalProjects/drama3-local/listening-r2"
STAGE = "/mnt/c/Users/bphan/AppData/Local/Temp/claude/C--Users-bphan-OneDrive-Desktop-codexProjectswindows-youtube/bed189eb-d50b-420a-9dad-0115191fc7e9/scratchpad/booth2"
sents = ["s06", "s10", "s11", "s19"]
rng = random.Random(20261020)
key = {}
for d in (LOCAL, STAGE):
    os.makedirs(f"{d}/takes", exist_ok=True)
for s in sents:
    items = [(b, seed) for b in ("Q4_K", "Q2_K") for seed in (1, 2, 3, 4)]
    rng.shuffle(items)
    for letter, (b, seed) in zip("ABCDEFGH", items):
        src = f"{R}/r2-{b.lower().replace('_', '')}/{s}-s{seed}.wav"
        for d in (LOCAL, STAGE):
            shutil.copy(src, f"{d}/takes/{s}-{letter}.wav")
        key[f"{s}-{letter}"] = {"build": b, "seed": seed}
json.dump(key, open(f"{LOCAL}/key-DO-NOT-OPEN-FIRST.json", "w"), indent=2)
print("packed", len(key))
