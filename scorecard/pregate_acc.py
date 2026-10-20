"""Accuracy of next-layer expert guesses (SPEECH_PREFETCH_EXPERTS=next with SPEECH_EXPERT_LOG).

The log holds, per graph, layer l's chosen experts and, under id 1000 + l, the guess made one layer earlier
from layer l-1's input. Prints the share of the guessed experts that layer l really chose (generated frames only)."""
import sys

from expert_stats import read_log

hit = total = 0
per_layer = {}
for _, rows, per in read_log(sys.argv[1], 8):
    if rows != 1:
        continue
    for key, guess in per.items():
        if key < 1000 or (key - 1000) not in per:
            continue
        actual = set(per[key - 1000][0])
        h = sum(1 for e in guess[0] if e in actual)
        hit += h
        total += len(guess[0])
        a = per_layer.setdefault(key - 1000, [0, 0])
        a[0] += h
        a[1] += len(guess[0])
print(f"guessed experts that the layer then chose: {100 * hit / max(total, 1):.1f}% of {total}")
worst = sorted(per_layer.items(), key=lambda kv: kv[1][0] / kv[1][1])[:5]
print("weakest layers:", ", ".join(f"{l}: {100 * a[0] / a[1]:.0f}%" for l, a in worst))
