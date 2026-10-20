#!/bin/bash
# Expert prefetch under RAM caps: none / same-layer / next-layer guess, at 12, 10 and 8 GB. Run as root (cgroup caps).
set -u
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
export BIN=/home/bphan944/drama3/speech.cpp-exp/build-tier/speech
for mode in none same next; do
  extra=()
  [ $mode != none ] && extra=(SPEECH_PREFETCH_EXPERTS=$mode)
  bash $SC/mmap_sweep.sh pf-$mode "12 10 8" "${extra[@]}"
done
echo PF-DONE
