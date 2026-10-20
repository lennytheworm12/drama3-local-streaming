#!/bin/bash
# Experiment 3b: does readahead (block-device read_ahead_kb, or madvise) speed up mmap streaming at a 10 GB cap?
# Run as root. Restores the device's original read_ahead_kb at the end.
set -u
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
DEV=$(basename $(df / | tail -1 | cut -d" " -f1))
RA=/sys/block/$DEV/queue/read_ahead_kb
ORIG=$(cat $RA)
echo "device $DEV read_ahead_kb was $ORIG"
for kb in 128 1024 4096; do
  echo $kb > $RA
  bash $SC/mmap_sweep.sh ra$kb "10"
done
echo $ORIG > $RA
bash $SC/mmap_sweep.sh ra${ORIG}-random "10" SPEECH_MADVISE=random
echo "restored read_ahead_kb to $(cat $RA)"
echo RA-DONE
