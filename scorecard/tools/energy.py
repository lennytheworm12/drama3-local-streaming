import wave, audioop, sys
for p in sys.argv[1:]:
    w = wave.open(p); sr = w.getframerate(); n = w.getnframes(); data = w.readframes(n)
    sec = []
    for i in range(0, n // sr):
        sec.append(audioop.rms(data[i*sr*2:(i+1)*sr*2], 2))
    line = "".join("." if r < 150 else ("o" if r < 1500 else "#") for r in sec)
    silent = sum(1 for r in sec if r < 150)
    print(p.split("/")[-1], f"{n/sr:.1f}s silent_s={silent}")
    for k in range(0, len(line), 60): print(f"  {k:4d}s {line[k:k+60]}")
