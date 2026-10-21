"""KL of several variants against a reference over many sentences, as one table.

    python kl_table.py DIR --refs f16 --variants e-pub e-imx --n 6

Reads DIR/<ref>-<i>.logits and DIR/<variant>-<i>.logits for i < n. Per variant: the main token's and the codebooks'
mean KL(ref || variant) over every matched step of every sentence, top-1 agreement, and the main token's KL per sentence.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import fidelity  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--refs", default="f16")
    ap.add_argument("--variants", nargs="+", required=True)
    ap.add_argument("--n", type=int, required=True)
    a = ap.parse_args()
    refs = [fidelity.read(os.path.join(a.dir, f"{a.refs}-{i}.logits")) for i in range(a.n)]
    print("| variant | main KL | main top-1 | codebook KL | codebook top-1 | main KL per sentence | unmatched |")
    print("|---|---|---|---|---|---|---|")
    for v in a.variants:
        main, books, per, missing = [0.0, 0, 0], [0.0, 0, 0], [], 0
        for i in range(a.n):
            path = os.path.join(a.dir, f"{v}-{i}.logits")
            if not os.path.exists(path):
                per.append("-")
                continue
            heads, miss = fidelity.compare(refs[i], fidelity.read(path))
            missing += miss
            m = heads.get(0, [0.0, 0, 0])
            per.append(f"{m[0] / m[2]:.3f}" if m[2] else "-")
            for h, acc in heads.items():
                into = main if h == 0 else books
                for k in range(3):
                    into[k] += acc[k]
        fmt = lambda x: f"{x[0] / x[2]:.4f}" if x[2] else "-"
        top = lambda x: f"{100 * x[1] / x[2]:.1f}%" if x[2] else "-"
        print(f"| {v} | {fmt(main)} | {top(main)} | {fmt(books)} | {top(books)} | {' '.join(per)} | {missing} |")


if __name__ == "__main__":
    main()
