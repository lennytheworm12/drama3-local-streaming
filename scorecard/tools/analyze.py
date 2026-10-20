import sys, re, os
d = os.path.expanduser(sys.argv[1])
def rd(n):
    p = os.path.join(d, n)
    return open(p, errors="replace").read() if os.path.exists(p) else ""
log = rd("speech.log") + rd("stderr.log")
m = re.search(r"Loaded drama-3 on (\S+) in ([\d.]+) s", log)
load_s = float(m.group(2)) if m else None
m = re.search(r"([\d.]+) s of audio in ([\d.]+) s, RTFx ([\d.]+), time to first audio ([\d.]+) s", log)
audio_s, gen_s, rtfx, ttfa = (float(x) for x in m.groups()) if m else (None,)*4
m = re.search(r"experts of (\d+) of its (\d+) layers", log)
layers = m.group(0) if m else "n/a"
rss = re.search(r"Maximum resident set size \(kbytes\): (\d+)", log)
fsin = re.search(r"File system inputs: (\d+)", log)
wall = re.search(r"Elapsed \(wall clock\) time .*: (\S+)", log)
# VRAM
v = [int(l.split(",")[1]) for l in rd("vram.csv").splitlines() if l.count(",") >= 2 and l.split(",")[1].strip().isdigit()]
# iostat: per-second rMB/s for sdd
r = []
for l in rd("vmstat.txt").splitlines()[3:]:
    f = l.split()
    if len(f) >= 17 and f[8].isdigit():
        r.append(int(f[8]) / 1024)  # vmstat bi = KiB/s read from block devices
n = len(r)
# assume generation is the last gen_s seconds of the run (before teardown)
gen_n = int(gen_s) if gen_s else 0
gen_r = r[-gen_n-2:-2] if gen_n and n > gen_n + 2 else []
rcm = re.search(r"rc=(\d+)", rd("summary.txt"))
print("exit:", rcm.group(1) if rcm else "?")
print(f"experts: {layers}")
print(f"load_s={load_s} audio_s={audio_s} gen_s={gen_s} rtfx={rtfx} ttfa_s={ttfa} wall={wall.group(1) if wall else None}")
if audio_s and gen_s:
    frames = audio_s / (2048/44100)
    print(f"frames~{frames:.0f} s_per_frame={gen_s/frames:.4f}")
print(f"peak_rss_GB={int(rss.group(1))/1048576:.2f}" if rss else "peak_rss n/a")
print(f"fs_inputs_GB={int(fsin.group(1))*512/1e9:.2f}" if fsin else "fs_inputs n/a")
print(f"vram_peak_MiB={max(v) if v else None} vram_min_MiB={min(v) if v else None} samples={len(v)}")
print(f"disk_read_total_MB={sum(r):.0f} peak_MBps={max(r) if r else 0:.0f}")
if gen_r: print(f"disk_read_during_generation: mean_MBps={sum(gen_r)/len(gen_r):.1f} max_MBps={max(gen_r):.1f} total_MB={sum(gen_r):.0f}")
