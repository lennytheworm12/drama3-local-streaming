"""Stage 2b: predicted naturalness (UTMOS22 strong) per take, and voice drift within long takes.

    ~/drama3/venv/bin/python mos.py RUN_DIR [RUN_DIR ...]

Writes mos.jsonl (id, seed, utmos, drift) per run dir and prints one row per run.
Drift: cosine similarity of ECAPA speaker embeddings of each 3 s window against the
take's first window, averaged; only for takes of 9 s or more (1.0 = no drift).
Runs on the CPU so it never competes with a model on the GPU.
"""
import json
import os
import statistics
import sys

import librosa
import torch

torch.set_num_threads(4)
mos_model = torch.hub.load("tarepan/SpeechMOS:v1.2.0", "utmos22_strong", trust_repo=True)
mos_model.eval()
from speechbrain.inference.speaker import EncoderClassifier  # noqa: E402

spk = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb",
                                     savedir=os.path.expanduser("~/drama3/models-aux/ecapa"),
                                     run_opts={"device": "cpu"})
SR = 16000
WIN = 3 * SR


def drift(wav):
    if len(wav) < 3 * WIN:
        return None
    wins = [wav[i:i + WIN] for i in range(0, len(wav) - WIN + 1, WIN)]
    with torch.no_grad():
        emb = spk.encode_batch(torch.tensor(wins)).squeeze(1)
    emb = torch.nn.functional.normalize(emb, dim=-1)
    return float((emb[1:] @ emb[0]).mean())


def score_dir(d):
    out = os.path.join(d, "mos.jsonl")
    done = set()
    if os.path.exists(out):
        done = {(r["id"], r["seed"]) for r in map(json.loads, open(out))}
    rows = [json.loads(l) for l in open(os.path.join(d, "gen.jsonl"))]
    with open(out, "a") as f:
        for g in rows:
            if (g["id"], g["seed"]) in done:
                continue
            wav, _ = librosa.load(os.path.join(d, g["wav"]), sr=SR, mono=True)
            with torch.no_grad():
                m = float(mos_model(torch.tensor(wav).unsqueeze(0), SR).item())
            f.write(json.dumps({"id": g["id"], "seed": g["seed"], "utmos": round(m, 3), "drift": drift(wav)}) + "\n")
            f.flush()
    res = [json.loads(l) for l in open(out)]
    mos = [r["utmos"] for r in res]
    dr = [r["drift"] for r in res if r["drift"] is not None]
    print(f"| {os.path.basename(d.rstrip('/'))} | {len(res)} | {statistics.mean(mos):.3f} | {min(mos):.2f} | "
          f"{statistics.mean(dr) if dr else float('nan'):.3f} |", flush=True)


if __name__ == "__main__":
    print("| run | takes | UTMOS mean | UTMOS min | voice drift sim (long takes) |")
    print("|---|---|---|---|---|")
    for d in sys.argv[1:]:
        score_dir(d)
