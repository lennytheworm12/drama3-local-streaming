#!/bin/bash
# Experiment 4b: hot experts on the GPU at several budgets, against the 4-whole-layers default; with step timing.
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
R=$HOME/drama3/scorecard-runs
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
SENT=s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20
run() {  # tag, extra env...
  local tag=$1; shift
  env SPEECH_MMAP=1 SPEECH_STEP_TIMING=1 "$@" python3 $SC/gen.py $tag --binary $BIN --seeds 1 --only ${ONLY:-$SENT} \
      ${CORPUS:+--corpus $CORPUS} > $R/$tag.log 2>&1
  echo "$tag rc=$? $(grep -h 'hot experts' $R/$tag/worker.stderr.log | tail -1) $(tail -1 $R/$tag.log)"
}
run tier-off
for gb in 1.0 1.7 2.2; do run tier-$gb SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=$gb; done
best=${BEST_GB:-1.7}
ONLY=c01,c02,c03,c04,c05,c06 CORPUS=$SC/corpus-contrast.jsonl run tier-contrast-off
ONLY=c01,c02,c03,c04,c05,c06 CORPUS=$SC/corpus-contrast.jsonl run tier-contrast-$best SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=$best
for d in $R/tier-*/; do python3 $SC/asr.py $d > $d/asr.log 2>&1; done
echo done
