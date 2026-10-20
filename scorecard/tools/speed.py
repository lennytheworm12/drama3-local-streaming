import json, sys, os, statistics
for d in sys.argv[1:]:
    g = [json.loads(l) for l in open(os.path.join(d, "gen.jsonl"))]
    g = [r for r in g if r["seed"] == 1 and r["id"].startswith("s")]
    a = sum(r["audio_s"] for r in g); t = sum(r["request_s"] for r in g)
    cfg = json.load(open(os.path.join(d, "config.json"))) if os.path.exists(os.path.join(d, "config.json")) else {}
    print(f"{os.path.basename(d)}: takes={len(g)} audio={a:.1f}s time={t:.1f}s rtfx={a/t:.3f} s/frame={t/(a/(2048/44100)):.4f} ttfa_p50={statistics.median(r['first_audio_s'] for r in g):.2f} load={cfg.get('load_s')} threads={cfg.get('threads')}")
