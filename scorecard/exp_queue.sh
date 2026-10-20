#!/bin/bash
# Runs experiments 1-4a and 3 in sequence, one GPU job at a time. Run as root (wsl -u root):
# dropping the page cache and the cgroup caps of the mmap sweep need it; every model run is the normal user's.
#   exp_queue.sh [steps...]   steps: threads load experts sweep score   (default: all, in that order)
set -u
U=bphan944; H=/home/$U
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
RUNS=$H/drama3/scorecard-runs
MAIN=$H/drama3/speech.cpp/build/speech
EXP=$H/drama3/speech.cpp-exp/build/speech
SENT=s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20
LOG=$RUNS/queue.log
as_user() { runuser -u $U -- env HOME=$H PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin "$@"; }
note() { echo "$(date '+%F %T') $*" | tee -a $LOG; }
cold() { sync; echo 3 > /proc/sys/vm/drop_caches; }
STEPS=${*:-threads load experts sweep score}

for step in $STEPS; do case $step in
threads)
  # Experiment 1: CPU threads for the 36 layers of experts the CPU computes. Same binary as the baseline.
  for t in 4 8 12 16; do
    note "threads $t start"
    as_user python3 $SC/gen.py threads-t$t --binary $MAIN --threads $t --seeds 1 --only $SENT > $RUNS/threads-t$t.log 2>&1
    note "threads $t rc=$? $(tail -1 $RUNS/threads-t$t.log)"
  done ;;
load)
  # Experiment 2: where the load time goes (read vs set per buffer), fread vs mmap, cold vs warm page cache.
  for mode in fread mmap; do for cache in cold warm; do
    tag=load-$mode-$cache
    [ $cache = cold ] && cold
    env_mmap=0; [ $mode = mmap ] && env_mmap=1
    note "$tag start"
    as_user env SPEECH_LOAD_TIMING=1 SPEECH_MMAP=$env_mmap python3 $SC/gen.py $tag --binary $EXP --seeds 1 --only s05 > $RUNS/$tag.log 2>&1
    note "$tag rc=$? $(grep -h 'experiment: load' $RUNS/$tag/worker.stderr.log | tail -1 | cut -c1-400)"
  done; done ;;
experts)
  # Experiment 4a: router picks per layer per frame, English corpus and a contrast set.
  rm -f $RUNS/experts-english.bin $RUNS/experts-contrast.bin
  note "experts english start"
  as_user env SPEECH_EXPERT_LOG=$RUNS/experts-english.bin python3 $SC/gen.py experts-english --binary $EXP --seeds 1 > $RUNS/experts-english.log 2>&1
  note "experts english rc=$?"
  as_user env SPEECH_EXPERT_LOG=$RUNS/experts-contrast.bin python3 $SC/gen.py experts-contrast --binary $EXP --seeds 1 \
      --corpus $SC/corpus-contrast.jsonl > $RUNS/experts-contrast.log 2>&1
  note "experts contrast rc=$?"
  as_user python3 $SC/expert_stats.py $RUNS/experts-english.bin $RUNS/experts-contrast.bin > $RUNS/experts-stats.md 2>&1
  note "experts stats written" ;;
sweep)
  # Experiment 3: mmap loader, speed against a RAM cap (cgroup MemoryMax), cold cache at every cap.
  note "sweep start"
  bash $SC/mmap_sweep.sh sweep "none 20 16 12 10 8" >> $LOG 2>&1
  note "sweep done" ;;
score)
  for d in $RUNS/threads-t* $RUNS/experts-english $RUNS/experts-contrast; do
    [ -f $d/gen.jsonl ] && as_user python3 $SC/asr.py $d > $d/asr.log 2>&1
  done
  as_user python3 $SC/score.py $RUNS/baseline-t8 $RUNS/threads-t4 $RUNS/threads-t8 $RUNS/threads-t12 $RUNS/threads-t16 \
      $RUNS/experts-english > $RUNS/score-queue.md 2>&1
  note "scored" ;;
esac; done
note "queue finished: $STEPS"
