"""Compare SPEECH_LOGITS dumps of a reference run and a variant replaying the same frames.

    python3 fidelity.py REF.logits VARIANT.logits

Record: int32 step, int32 head (0 = main token, 1 + b = codebook b), int32 count, count float32.
Reports per head: mean KL(ref || variant) in nats, top-1 agreement, and steps compared.
Records are matched by (step, head); a missing match is counted and reported.
"""
import array
import collections
import math
import struct
import sys


def read(path):
    out = {}
    with open(path, "rb") as f:
        data = f.read()
    i = 0
    while i + 12 <= len(data):
        step, head, n = struct.unpack_from("<iii", data, i)
        i += 12
        v = array.array("f")
        v.frombytes(data[i:i + 4 * n])
        i += 4 * n
        out[(step, head)] = v
    return out


def log_softmax(v):
    m = max(v)
    s = math.log(sum(math.exp(x - m) for x in v))
    return [x - m - s for x in v]


def kl(p_logits, q_logits):
    lp, lq = log_softmax(p_logits), log_softmax(q_logits)
    return sum(math.exp(a) * (a - b) for a, b in zip(lp, lq) if a > -30)


def argmax(v):
    return max(range(len(v)), key=v.__getitem__)


def compare(ref, var):
    per_head = collections.defaultdict(lambda: [0.0, 0, 0])  # kl sum, top1 agree, n
    missing = 0
    for key, r in ref.items():
        q = var.get(key)
        if q is None or len(q) != len(r):
            missing += 1
            continue
        acc = per_head[key[1]]
        acc[0] += kl(r, q)
        acc[1] += argmax(r) == argmax(q)
        acc[2] += 1
    return per_head, missing


def sampled(logits, top_k=30, top_p=0.9):
    """The distribution Drama 3's sampler draws from: the top_k by probability, those within top_p (the first always),
    renormalized. Returns {token: probability}."""
    lp = log_softmax(logits)
    order = sorted(range(len(lp)), key=lambda i: -lp[i])[:top_k]
    kept, cum = [], 0.0
    for r, i in enumerate(order):
        cum += math.exp(lp[i])
        if r > 0 and cum > top_p:
            break
        kept.append(i)
    total = sum(math.exp(lp[i]) for i in kept)
    return {i: math.exp(lp[i]) / total for i in kept}


def acceptance(ref, var, head=0):
    """Speculative sampling's expected acceptance of a token drawn from `var` (the draft) when `ref` (the full model)
    verifies it: the mean over steps of sum_t min(p_ref(t), p_var(t)), on the sampler's truncated distributions."""
    vals = []
    for key, r in ref.items():
        if key[1] != head or key not in var:
            continue
        p, q = sampled(r), sampled(var[key])
        vals.append(sum(min(p.get(t, 0.0), q.get(t, 0.0)) for t in set(p) | set(q)))
    return sum(vals) / len(vals) if vals else float("nan")


def main():
    ref, var = read(sys.argv[1]), read(sys.argv[2])
    per_head, missing = compare(ref, var)
    print(f"speculative acceptance of the main token (draft = second file): {100 * acceptance(ref, var):.1f}%")
    print("| head | steps | mean KL (nats) | top-1 agreement |")
    print("|---|---|---|---|")
    tot = [0.0, 0, 0]
    for head in sorted(per_head):
        s, a, n = per_head[head]
        name = "main" if head == 0 else f"codebook {head - 1}"
        print(f"| {name} | {n} | {s / n:.5f} | {100 * a / n:.1f}% |")
        if head > 0:
            tot = [tot[0] + s, tot[1] + a, tot[2] + n]
    if tot[2]:
        print(f"| all codebooks | {tot[2]} | {tot[0] / tot[2]:.5f} | {100 * tot[1] / tot[2]:.1f}% |")
    print(f"unmatched records: {missing}")


if __name__ == "__main__":
    main()
