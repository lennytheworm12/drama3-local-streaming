import json, collections, statistics, math
key = json.load(open("C:/Users/bphan/PersonalProjects/drama3-local/listening-r2/key-DO-NOT-OPEN-FIRST.json"))
raw = """s06: AN3 BW4 CW3 DW3 EW3 FW3 GW4 HN3
s10: AW3 BN3 CW4 DW4 EN3 FW3 GN3 HW4
s11: AN3 BN3 CN3 DW3 EN3 FN3 GW4 HW4
s19: AW4 BN2 CN3 DW4 EW4 FN3 GN2 HW3"""
watch = collections.defaultdict(list); score = collections.defaultdict(list); per = collections.defaultdict(lambda: collections.defaultdict(list))
for line in raw.splitlines():
    sid, rest = line.split(": ")
    for tok in rest.split():
        k = key[f"{sid}-{tok[0]}"]; b = k["build"]
        watch[b].append(tok[1] == "W"); score[b].append(int(tok[2])); per[sid][b].append(f"{tok[0]}:{tok[1]}{tok[2]}(seed{k['seed']})")
for b in ("Q4_K", "Q2_K"):
    w = sum(watch[b]); n = len(watch[b])
    print(f"{b}: would watch {w}/{n} = {100*w/n:.0f}%, mean score {statistics.mean(score[b]):.2f}, 4+ = {sum(s>=4 for s in score[b])}")
# Fisher exact two-sided on watch counts
a, b_ = sum(watch['Q4_K']), sum(watch['Q2_K']); n1 = n2 = 16
def C(n, k): return math.comb(n, k)
tot = a + b_; pobs = C(n1, a) * C(n2, b_) / C(32, tot)
p = sum(C(n1, x) * C(n2, tot - x) / C(32, tot) for x in range(max(0, tot - n2), min(n1, tot) + 1) if C(n1, x) * C(n2, tot - x) / C(32, tot) <= pobs + 1e-12)
print(f"Fisher exact p (watch rate difference) = {p:.2f}")
for sid in per:
    print(sid, {b: per[sid][b] for b in per[sid]})
for note in ["s06-H", "s10-B", "s19-B"]:
    print(note, key[note])
