cd ~/drama3/scorecard-runs
for d in load-fread-cold load-fread-warm load-mmap-cold load-mmap-warm; do
  echo "== $d"; cat $d/gen.jsonl | cut -c1-400
  python3 -c "import json,sys;c=json.load(open(sys.argv[1]));print('load_s',c['load_s'],'peak',c['peak'])" $d/config.json
done
md5sum baseline-t8/s05-s1.wav load-*/s05-s1.wav
