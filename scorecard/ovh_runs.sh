#!/bin/bash
# Per-layer handoff overhead and the hot-expert NaN bisect. 10 sentences, seed 1, mmap, warm cache.
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
R=$HOME/drama3/scorecard-runs
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
ONLY=s01,s02,s03,s04,s06,s07,s10,s11,s14,s19
: > $R/empty-hot.txt
run() {
  local tag=$1; shift
  env SPEECH_MMAP=1 SPEECH_STEP_TIMING=1 "$@" python3 $SC/gen.py $tag --binary $BIN --seeds 1 --only $ONLY > $R/$tag.log 2>&1
  echo "$tag rc=$? $(tail -1 $R/$tag.log | cut -c1-200)"
}
run ovh-held4                                                   # default: 4 layers' experts on the GPU
run ovh-held0 SPEECH_HOT_EXPERTS=$R/empty-hot.txt SPEECH_HOT_GB=0  # every layer's experts on the CPU
run ovh-held4-poll100 SPEECH_POLL=100
run ovh-held4-poll0 SPEECH_POLL=0
run ovh-hot1.0 SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=1.0
run ovh-hot1.0-noskip SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=1.0 SPEECH_HOT_NOSKIP=1
python3 /mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard/tools/steps.py $R/ovh-*/
echo done
