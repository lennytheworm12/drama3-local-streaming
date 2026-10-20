"""Analyze SPEECH_EXPERT_LOG files written by the patched speech.cpp (exp branch).

Record (int32 little-endian): n_past, rows, layers, then per layer: layer index,
rows*used expert ids (row-major: row r's `used` ids together).

    python3 expert_stats.py LOG [LOG2] [--used 8 --experts 256 --expert-mb 1.75]

Reports, for generated frames (rows == 1) and prompt rows separately where useful:
- coverage: share of picks covered by each layer's top X% experts
- global hot set: share of picks covered when the hottest N experts across all
  layers are pinned (N from VRAM/RAM budgets in GB)
- locality: share of a frame's picks that the previous frame also used (same layer)
- LRU cache simulation: misses per frame for a cache of B GB of experts
- overlap: Jaccard of the top-30% sets of LOG and LOG2 (if given)
"""
import argparse
import collections
import struct


def read_log(path, used):
    """Yields (n_past, rows, {layer: [[ids of row 0], [ids of row 1], ...]})."""
    with open(path, "rb") as f:
        data = f.read()
    i, n = 0, len(data)
    while i + 12 <= n:
        n_past, rows, layers = struct.unpack_from("<iii", data, i)
        i += 12
        per = {}
        for _ in range(layers):
            (layer,) = struct.unpack_from("<i", data, i)
            i += 4
            cnt = rows * used
            ids = struct.unpack_from(f"<{cnt}i", data, i)
            i += 4 * cnt
            per[layer] = [ids[r * used:(r + 1) * used] for r in range(rows)]
        yield n_past, rows, per


def frames_and_prompt(path, used):
    """Generated frames as a list of {layer: ids}; prompt picks as Counter keyed (layer, expert)."""
    frames, prompt = [], collections.Counter()
    for _, rows, per in read_log(path, used):
        if rows == 1:
            frames.append({l: v[0] for l, v in per.items()})
        else:
            for l, rr in per.items():
                for ids in rr:
                    prompt.update((l, e) for e in ids)
    return frames, prompt


def counts(frames):
    c = collections.Counter()
    for fr in frames:
        for l, ids in fr.items():
            c.update((l, e) for e in ids)
    return c


def coverage_per_layer(c, experts, fractions):
    by_layer = collections.defaultdict(list)
    for (l, _), v in c.items():
        by_layer[l].append(v)
    out = {}
    for frac in fractions:
        k = max(1, round(experts * frac))
        covered = total = 0
        for vals in by_layer.values():
            vals.sort(reverse=True)
            covered += sum(vals[:k])
            total += sum(vals)
        out[frac] = covered / total if total else 0.0
    used_any = sum(len(v) for v in by_layer.values())
    return out, used_any


def hot_set_coverage(c, n_hot):
    total = sum(c.values())
    top = sum(v for _, v in c.most_common(n_hot))
    return top / total if total else 0.0


def locality(frames):
    hit = total = 0
    for prev, cur in zip(frames, frames[1:]):
        for l, ids in cur.items():
            p = set(prev.get(l, ()))
            hit += sum(1 for e in ids if e in p)
            total += len(ids)
    return hit / total if total else 0.0


def lru_misses_per_frame(frames, capacity, pinned=frozenset()):
    """Global LRU over (layer, expert) with `capacity` slots, plus never-evicted `pinned` ones."""
    cache = collections.OrderedDict()
    misses = 0
    for fr in frames:
        for l, ids in fr.items():
            for e in ids:
                key = (l, e)
                if key in pinned:
                    continue
                if key in cache:
                    cache.move_to_end(key)
                else:
                    misses += 1
                    cache[key] = True
                    if len(cache) > capacity:
                        cache.popitem(last=False)
    return misses / len(frames) if frames else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("log2", nargs="?")
    ap.add_argument("--used", type=int, default=8)
    ap.add_argument("--experts", type=int, default=256)
    ap.add_argument("--layers", type=int, default=40)
    ap.add_argument("--expert-mb", type=float, default=1.75)
    ap.add_argument("--hot-list", help="write 'layer expert' lines, hottest first, for SPEECH_HOT_EXPERTS")
    a = ap.parse_args()

    frames, prompt = frames_and_prompt(a.log, a.used)
    c = counts(frames)
    if a.hot_list:
        with open(a.hot_list, "w") as f:
            for (layer, expert), _ in c.most_common():
                f.write(f"{layer} {expert}\n")
        print(f"wrote {len(c)} ranked experts to {a.hot_list}")
        return
    slots = a.experts * a.layers
    print(f"generated frames: {len(frames)}, picks: {sum(c.values())}, prompt picks: {sum(prompt.values())}")
    cov, used_any = coverage_per_layer(c, a.experts, [0.05, 0.1, 0.2, 0.3, 0.5])
    print(f"experts ever picked in generation: {used_any} of {slots} ({100 * used_any / slots:.1f}%)")
    print("per-layer top-X% coverage of generation picks: " +
          ", ".join(f"top {int(f * 100)}% -> {100 * v:.1f}%" for f, v in cov.items()))
    print(f"frame-to-frame reuse (same layer): {100 * locality(frames):.1f}%")
    print("global hot set (pinned hottest experts) and LRU cache for the rest:")
    print("| pinned GB | pinned experts | coverage | + LRU GB | misses/frame | miss MB/frame |")
    print("|---|---|---|---|---|---|")
    for pin_gb in (0, 1, 2, 4):
        n_pin = int(pin_gb * 1024 / a.expert_mb)
        pinned = frozenset(k for k, _ in c.most_common(n_pin))
        for lru_gb in (2, 4, 8, 12):
            cap = int(lru_gb * 1024 / a.expert_mb)
            m = lru_misses_per_frame(frames, cap, pinned)
            print(f"| {pin_gb} | {n_pin} | {100 * hot_set_coverage(c, n_pin):.1f}% | {lru_gb} | {m:.2f} | {m * a.expert_mb:.1f} |")
    if a.log2:
        f2, _ = frames_and_prompt(a.log2, a.used)
        c2 = counts(f2)
        k = int(0.3 * slots)
        s1 = {x for x, _ in c.most_common(k)}
        s2 = {x for x, _ in c2.most_common(k)}
        j = len(s1 & s2) / len(s1 | s2) if s1 | s2 else 0.0
        cross = sum(v for x, v in c2.items() if x in s1) / max(sum(c2.values()), 1)
        print(f"top-30% overlap (Jaccard) with {a.log2}: {100 * j:.1f}%; "
              f"share of LOG2's picks covered by LOG's top 30%: {100 * cross:.1f}%")


if __name__ == "__main__":
    main()
