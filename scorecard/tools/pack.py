import json, os, random, shutil
R = os.path.expanduser("~/drama3/scorecard-runs")
OUT = "/mnt/c/Users/bphan/PersonalProjects/drama3-local/listening"
variants = {"Q4_K (published)": "q-ctl-q4k", "IQ4_XS experts": "q-exps-iq4xs", "Q3_K experts": "q-exps-q3k",
            "IQ3_S experts": "q-exps-iq3s", "Q2_K experts": "q-exps-q2k"}
sents = ["s04", "s06", "s10", "s11", "s14", "s19"]
texts = {json.loads(l)["id"]: json.loads(l)["text"] for l in open(f"{R}/q-ctl-q4k/gen.jsonl")}
rng = random.Random(20261019)
os.makedirs(f"{OUT}/blind", exist_ok=True)
key, lines = {}, []
for s in sents:
    order = list(variants.items()); rng.shuffle(order)
    lines.append(f"## {s}: \"{texts[s]}\"\n")
    for letter, (name, run) in zip("ABCDE", order):
        dst = f"blind/{s}-{letter}.wav"
        shutil.copy(f"{R}/{run}/{s}-s1.wav", f"{OUT}/{dst}")
        key[f"{s}-{letter}"] = name
        lines.append(f"- {letter}: `{dst}` — rating: ___ (1-5)  notes: ")
    lines.append("")
json.dump(key, open(f"{OUT}/key-DO-NOT-OPEN-FIRST.json", "w"), indent=2)
# reference extras, labelled
os.makedirs(f"{OUT}/labelled", exist_ok=True)
extras = [("baseline-t8/p01-s1.wav", "paragraph-q4k-seed1-clean.wav"),
          ("baseline-t8/p01-s2.wav", "paragraph-q4k-seed2-runaway-dead-air.wav"),
          ("baseline-t8/p01-s3.wav", "paragraph-q4k-seed3-runaway-murmur.wav"),
          ("baseline-t8/s05-s1.wav", "s05-honestly-dropped-words.wav"),
          ("tier-2.2/s05-s1.wav", "s05-hot-expert-tiering-low-utmos.wav")]
for src, dst in extras:
    shutil.copy(f"{R}/{src}", f"{OUT}/labelled/{dst}")
open(f"{OUT}/index.md", "w").write(
    "# Drama 3 listening pack (blind)\n\nEach sentence has 5 takes, A–E: the same seed and text from 5 quant variants "
    "(published Q4_K; experts at IQ4_XS, Q3_K, IQ3_S, Q2_K). The order is shuffled per sentence. Rate each 1–5 before "
    "opening `key-DO-NOT-OPEN-FIRST.json`. Expect different takes to differ a little anyway (different weights, "
    "so different samples).\n\n" + "\n".join(lines) +
    "\n## Labelled examples (not blind)\n\n" + "\n".join(f"- `labelled/{d}`" for _, d in extras) + "\n")
print("ok", len(key))
