"""Japanese CER on kana readings (OpenJTalk), so that 24 and 二十四, or 他 and ほか, count as the same speech.

    ~/drama3/venv/bin/python kana_cer.py RUN_DIR [RUN_DIR ...]   (after score.py has written takes.jsonl)

This approximates speech-bench's "error rate with accepted spellings" (readings in kana are accepted) without its
hand-made annotations. Residual false errors: Latin words read letter by letter (Slack -> エスエルエーシーケー
against スラック) and readings OpenJTalk gets wrong.
"""
import json
import os
import statistics
import sys

import pyopenjtalk

from score import edit_distance


def kana(text):
    k = pyopenjtalk.g2p(text, kana=True)
    return "".join(ch for ch in k if "゠" <= ch <= "ヿ")  # katakana and ー only


def main():
    print("| run | takes | plain CER (mean of takes) | kana CER (mean of takes) | kana CER (pooled) | takes with kana CER > 10% |")
    print("|---|---|---|---|---|---|")
    for d in sys.argv[1:]:
        takes = [json.loads(l) for l in open(os.path.join(d, "takes.jsonl"))]
        plain, kcer, bad, edits, chars = [], [], 0, 0, 0
        worst = []
        for t in takes:
            r, h = kana(t["text"]), kana(t["hyp"])
            e = edit_distance(r, h)
            c = e / max(len(r), 1)
            kcer.append(c)
            plain.append(t["cer"])
            edits += e
            chars += len(r)
            bad += c > 0.10
            if c > 0.10:
                worst.append(f"{t['id']}-s{t['seed']} {c:.2f}")
        print(f"| {os.path.basename(d.rstrip('/'))} | {len(takes)} | {100 * statistics.mean(plain):.1f}% | "
              f"{100 * statistics.mean(kcer):.1f}% | {100 * edits / max(chars, 1):.1f}% | {bad} |")
        print("  over 10%: " + ", ".join(worst), file=sys.stderr)


if __name__ == "__main__":
    main()
