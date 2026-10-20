"""Speaker similarity (ECAPA cosine) of each take to a reference clip; voice-file takes against voice-none takes."""
import sys, glob, os
import librosa, torch
from speechbrain.inference.speaker import EncoderClassifier
spk = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb", savedir=os.path.expanduser("~/drama3/models-aux/ecapa"), run_opts={"device": "cpu"})
def emb(p):
    w, _ = librosa.load(p, sr=16000)
    with torch.no_grad():
        return torch.nn.functional.normalize(spk.encode_batch(torch.tensor(w)[None]).squeeze(), dim=0)
ref = emb(sys.argv[1])
for label, pattern in zip(sys.argv[2::2], sys.argv[3::2]):
    sims = [float(emb(p) @ ref) for p in sorted(glob.glob(pattern))]
    print(f"{label}: n={len(sims)} mean={sum(sims)/len(sims):.3f} min={min(sims):.3f} max={max(sims):.3f}")
