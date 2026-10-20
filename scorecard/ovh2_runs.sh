#!/bin/bash
# Re-run of the two failed overhead cases after the fixes (empty hot list; hot tensors padded to >= 8 slots).
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
R=$HOME/drama3/scorecard-runs
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
ONLY=s01,s02,s03,s04,s06,s07,s10,s11,s14,s19
run() {
  local tag=$1; shift
  rm -rf $R/$tag
  env SPEECH_MMAP=1 SPEECH_STEP_TIMING=1 "$@" python3 $SC/gen.py $tag --binary $BIN --seeds 1 --only $ONLY > $R/$tag.log 2>&1
  echo "$tag rc=$? $(tail -1 $R/$tag.log | cut -c1-200)"
}
run ovh-held0 SPEECH_HOT_EXPERTS=$R/empty-hot.txt SPEECH_HOT_GB=0
run ovh-hot1.0 SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=1.0
run ovh-hot2.2 SPEECH_HOT_EXPERTS=$R/hot-english.txt SPEECH_HOT_GB=2.2
python3 /mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard/tools/steps.py $R/ovh-held4/ $R/ovh-held0/ $R/ovh-hot1.0/ $R/ovh-hot2.2/
echo ovh2 done
