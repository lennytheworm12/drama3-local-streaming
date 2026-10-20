"""Sums ggml-vulkan's GGML_VK_PERF_LOGGER prints over a whole log: per op, its count and GPU time.

    python vk_perf_sum.py worker.log [--frames N]

Each print is one submitted graph's ops; this adds them up, so with --frames the times read per frame.
"""
import argparse
import codecs
import collections
import re

LINE = re.compile(r"^(.*): (\d+) x ([\d.e+-]+) us = ([\d.e+-]+) us")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--frames", type=int, default=1)
    ap.add_argument("--top", type=int, default=30)
    a = ap.parse_args()
    count, total = collections.Counter(), collections.Counter()
    with open(a.log, "rb") as raw:
        head = raw.read(2)
    # PowerShell's 2> writes UTF-16.
    enc = "utf-16" if head in (codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE) else "utf-8"
    with open(a.log, encoding=enc, errors="replace") as f:
        for line in f:
            m = LINE.match(line.strip())
            if m:
                count[m.group(1)] += int(m.group(2))
                total[m.group(1)] += float(m.group(4))
    grand = sum(total.values())
    if not grand:
        raise SystemExit(f"{a.log} holds no Vulkan timings")
    print(f"GPU op time {grand / 1000 / a.frames:.2f} ms per frame, {sum(count.values()) / a.frames:.0f} ops per frame")
    print("| op | per frame | ms per frame | share |")
    print("|---|---|---|---|")
    for op, t in total.most_common(a.top):
        print(f"| {op} | {count[op] / a.frames:.1f} | {t / 1000 / a.frames:.3f} | {100 * t / grand:.1f}% |")


if __name__ == "__main__":
    main()
