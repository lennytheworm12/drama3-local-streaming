"""Stage 3: score runs. Pure: reads gen.jsonl, asr.jsonl, config.json and the WAVs.

    python3 score.py RUN_DIR [RUN_DIR ...]

Writes takes.jsonl + score.json into each run dir and prints one markdown table
(one row per run) plus the flagged takes.
"""
import array
import json
import math
import os
import re
import statistics
import sys
import unicodedata
import wave

# ---------- text normalization (shared by reference and ASR hypothesis) ----------

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()


def _below_100(n):
    return ONES[n] if n < 20 else TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])


def _below_10000(n):
    if n < 100:
        return _below_100(n)
    if n < 1000:
        rest = n % 100
        return ONES[n // 100] + " hundred" + (" " + _below_100(rest) if rest else "")
    rest = n % 1000
    return _below_100(n // 1000) + " thousand" + (" " + _below_10000(rest) if rest else "")


def number_words(n, year_style):
    if year_style and 1100 <= n <= 2099 and n % 100 != 0 and not (2000 <= n <= 2009):
        return _below_100(n // 100) + " " + (_below_100(n % 100) if n % 100 >= 10 else "oh " + ONES[n % 100])
    if n < 10000:
        return _below_10000(n)
    return " ".join(ONES[int(d)] for d in str(n))


def normalize(text):
    t = text.lower().replace("’", "'")
    t = re.sub(r"(\d{1,2}):(\d{2})", lambda m: f"{m.group(1)} {m.group(2)}", t)
    t = re.sub(r"(?<=\d),(?=\d{3})", "", t)
    t = re.sub(r"\d+", lambda m: " " + number_words(int(m.group()), len(m.group()) == 4) + " ", t)
    t = t.replace("dr.", "doctor").replace("mt.", "mount")
    t = re.sub(r"[-–—]", " ", t)
    t = re.sub(r"[^a-z' ]", " ", t)
    # apostrophes count only inside a word (let's), not as quote marks
    return " ".join(w.strip("'") for w in t.split() if w.strip("'"))


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def is_cjk(text):
    return any("぀" <= ch <= "ヿ" or "一" <= ch <= "鿿" for ch in text)


def normalize_cjk(text):
    """Characters only: NFKC, then punctuation, symbols and spaces dropped. Numeral spellings are not unified."""
    t = unicodedata.normalize("NFKC", text).lower()
    return "".join(ch for ch in t if not unicodedata.category(ch)[0] in "PSZ")


def error_rates(ref, hyp):
    if is_cjk(ref):
        r, h = normalize_cjk(ref), normalize_cjk(hyp)
        cer = edit_distance(r, h) / max(len(r), 1)
        return cer, cer, len(r)  # no word boundaries: WER is reported as CER, words as characters
    r, h = normalize(ref), normalize(hyp)
    rw = r.split()
    wer = edit_distance(rw, h.split()) / max(len(rw), 1)
    cer = edit_distance(r, h) / max(len(r), 1)
    return wer, cer, len(rw)


# ---------- audio checks ----------

FRAME_S = 0.05
SILENCE_DBFS = -45.0


def audio_stats(path):
    with wave.open(path) as f:
        sr, n = f.getframerate(), f.getnframes()
        samples = array.array("h", f.readframes(n))
    hop = int(sr * FRAME_S)
    loud = []
    for i in range(0, len(samples) - hop + 1, hop):
        seg = samples[i:i + hop]
        rms = math.sqrt(sum(s * s for s in seg) / hop) or 1e-9
        loud.append(20 * math.log10(rms / 32768) > SILENCE_DBFS)
    if not any(loud):
        return {"silence_share": 1.0, "longest_pause_s": n / sr}
    first, last = loud.index(True), len(loud) - 1 - loud[::-1].index(True)
    inner = loud[first:last + 1]
    longest = run = 0
    for v in inner:
        run = 0 if v else run + 1
        longest = max(longest, run)
    return {"silence_share": round(1 - sum(inner) / len(inner), 3),
            "longest_pause_s": round(longest * FRAME_S, 2)}


# ---------- per-take flags ----------

def flags(t):
    out = []
    if t["stop"] != "complete":
        out.append(t["stop"])
    if t["wer"] > 0.2:
        out.append("wer>20%")
    if t["longest_pause_s"] > 2.0:
        out.append("pause>2s")
    if not t.get("cjk") and not 1.5 <= t["words_per_s"] <= 4.5:  # the rate bounds are English words per second
        out.append("rate")
    return out


def read_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def score_run(d):
    gen = read_jsonl(os.path.join(d, "gen.jsonl"))
    asr = {(r["id"], r["seed"]): r for r in read_jsonl(os.path.join(d, "asr.jsonl"))}
    cfg_path = os.path.join(d, "config.json")
    cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
    takes = []
    for g in gen:
        a = asr.get((g["id"], g["seed"]))
        if a is None:
            continue
        wer, cer, nwords = error_rates(g["text"], a["hyp"])
        t = {**g, "hyp": a["hyp"], "wer": round(wer, 4), "cer": round(cer, 4), "cjk": is_cjk(g["text"]),
             "words_per_s": round(nwords / g["audio_s"], 2) if g["audio_s"] else 0.0,
             **audio_stats(os.path.join(d, g["wav"]))}
        t["flags"] = flags(t)
        takes.append(t)
    with open(os.path.join(d, "takes.jsonl"), "w", encoding="utf-8") as f:
        for t in takes:
            f.write(json.dumps(t, ensure_ascii=False) + "\n")

    def med(key, rows=takes):
        vals = [r[key] for r in rows if r.get(key) is not None]
        return round(statistics.median(vals), 3) if vals else None

    sentences = [t for t in takes if t["id"].startswith("s")]
    total_audio = sum(t["audio_s"] for t in takes)
    total_req = sum(t["request_s"] for t in takes)
    peak = cfg.get("peak", {})
    s = {"tag": cfg.get("tag", os.path.basename(d)), "takes": len(takes),
         "wer_mean": round(statistics.mean(t["wer"] for t in takes), 4) if takes else None,
         "cer_mean": round(statistics.mean(t["cer"] for t in takes), 4) if takes else None,
         "sentence_wer_mean": round(statistics.mean(t["wer"] for t in sentences), 4) if sentences else None,
         "flagged": sum(1 for t in takes if t["flags"]),
         "not_complete": sum(1 for t in takes if t["stop"] != "complete"),
         "rtfx_overall": round(total_audio / total_req, 3) if total_req else None,
         "first_audio_s_median": med("first_audio_s"),
         "load_s": cfg.get("load_s"), "threads": cfg.get("threads"),
         "peak_rss_gb": round(peak.get("rss_kb", 0) / 1048576, 2),
         "peak_anon_gb": round(peak.get("anon_kb", 0) / 1048576, 2),
         "peak_vram_mib": peak.get("vram_mib"), "baseline_vram_mib": cfg.get("baseline_vram_mib")}
    with open(os.path.join(d, "score.json"), "w") as f:
        json.dump(s, f, indent=2)
    return s, takes


def pct(x):
    return "—" if x is None else f"{100 * x:.1f}%"


def main():
    rows = []
    for d in sys.argv[1:]:
        s, takes = score_run(d)
        rows.append((s, takes))
    print("| run | takes | WER | CER | sentence WER | flagged | not complete | RTFx | first audio p50 | load | threads | peak RSS (anon) | peak VRAM |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for s, _ in rows:
        print(f"| {s['tag']} | {s['takes']} | {pct(s['wer_mean'])} | {pct(s['cer_mean'])} | {pct(s['sentence_wer_mean'])} | "
              f"{s['flagged']} | {s['not_complete']} | {s['rtfx_overall']} | {s['first_audio_s_median']} s | "
              f"{s['load_s']} s | {s['threads']} | {s['peak_rss_gb']} GB ({s['peak_anon_gb']}) | "
              f"{s['peak_vram_mib']} MiB (base {s['baseline_vram_mib']}) |")
    for s, takes in rows:
        bad = [t for t in takes if t["flags"]]
        if bad:
            print(f"\nFlagged in {s['tag']}:")
            for t in bad:
                print(f"- {t['id']}-s{t['seed']}: {', '.join(t['flags'])}; WER {pct(t['wer'])}, "
                      f"{t['audio_s']} s, pause {t['longest_pause_s']} s; hyp: {t['hyp'][:120]}")


if __name__ == "__main__":
    main()
