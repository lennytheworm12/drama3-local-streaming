#!/bin/bash
# usage: run.sh TAG SEED
TAG=$1; SEED=$2
OUT=~/drama3/runs/$TAG; mkdir -p $OUT; cd $OUT
WIN=/mnt/c/Users/bphan/PersonalProjects/drama3-local/step1
TEXT=$(tr '\n' ' ' < $WIN/narration.txt | sed 's/  */ /g')
BIN=~/drama3/speech.cpp/build/speech
MODEL=~/models/Drama-35B-A3B-v3-Q4_K.gguf
sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu --format=csv,noheader,nounits -lms 1000 > vram.csv &
NV=$!
iostat -x -m -y 1 $(basename $(df / | tail -1 | cut -d" " -f1)) > iostat.txt &
IO=$!
vmstat -n 1 > vmstat.txt &
VM=$!
( while sleep 1; do p=$(pgrep -x speech | head -1); [ -n "$p" ] && echo "$(date +%s) $(grep -E '^(VmRSS|RssAnon|RssFile)' /proc/$p/status | awk '{printf "%s %s ",$1,$2}')"; done ) > rss.txt &
RS=$!
( sleep 120; p=$(pgrep -x speech | head -1); [ -n "$p" ] && cat /proc/$p/smaps_rollup > smaps_rollup.txt ) &
START=$(date +%s.%N)
/usr/bin/time -v $BIN tts $MODEL --voice none --seed $SEED -v -o out.wav "$TEXT" > speech.log 2> stderr.log
RC=$?
END=$(date +%s.%N)
kill $NV $IO $VM $RS 2>/dev/null
echo "rc=$RC wall=$(python3 -c "print(round($END-$START,2))")" > summary.txt
python3 - >> summary.txt <<'PY'
import wave
w=wave.open("out.wav"); d=w.getnframes()/w.getframerate(); print(f"audio_s={d:.2f} frames_est={d/ (2048/44100):.0f}")
PY
mkdir -p $WIN && cp out.wav $WIN/$TAG.wav
cat summary.txt
