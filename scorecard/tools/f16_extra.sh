#!/bin/bash
# F16 on the CPU (mmap) replays the extra recordings rec-2..5 that Windows made: the reference logits f16-2..5.
set -u
W=/mnt/c/Users/bphan/PersonalProjects/drama3-local/win/fidelity
BIN=$HOME/drama3/speech.cpp-exp/build-cpu/speech
F16=$HOME/models/Drama-35B-A3B-v3-F16.gguf
mapfile -t TEXTS < /mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard/fidelity-extra.txt
for i in "${!TEXTS[@]}"; do
  n=$((i + 2))
  t="${TEXTS[$i]%$'\r'}"
  rm -f $W/f16-$n.logits
  t0=$(date +%s)
  SPEECH_MMAP=1 SPEECH_MIXED_OK=1 SPEECH_FORCE=$W/rec-$n.bin SPEECH_LOGITS=/tmp/f16-$n.logits \
    $BIN tts $F16 --device cpu --threads 8 --voice none --seed 1 -o /tmp/f16-$n.wav "$t" > /tmp/f16-$n.log 2>&1
  rc=$?
  mv /tmp/f16-$n.logits $W/f16-$n.logits
  echo "f16 $n rc=$rc $(( $(date +%s) - t0 )) s"
done
echo F16X-DONE
