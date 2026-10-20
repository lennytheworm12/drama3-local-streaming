#!/bin/bash
# Experiment 3: speed vs RAM cap with the mmap loader. Run as root (wsl -u root) so systemd-run can
# put each run in a scope with MemoryMax; the run itself is executed as the normal user.
#   mmap_sweep.sh TAG_PREFIX "28 20 16 12 10 8" [extra env, e.g. SPEECH_MADVISE=random]
set -u
PREFIX=$1; CAPS=$2; shift 2
U=bphan944; H=/home/$U
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
BIN=${BIN:-$H/drama3/speech.cpp-exp/build/speech}
ONLY=s01,s04,s06,s11,s19
for cap in $CAPS; do
  tag=$PREFIX-cap$cap
  out=$H/drama3/scorecard-runs/$tag; mkdir -p $out; chown $U:$U $out
  sync; echo 3 > /proc/sys/vm/drop_caches   # cold start for every cap
  vmstat -n 1 > $out/vmstat.txt & VM=$!
  limit=()
  [ "$cap" != "none" ] && limit=(-p MemoryMax=${cap}G -p MemorySwapMax=0)
  timeout 2400 systemd-run --scope --quiet --uid=$U --gid=$U "${limit[@]}" \
    env HOME=$H PATH=/usr/lib/wsl/lib:/usr/local/bin:/usr/bin:/bin SPEECH_MMAP=1 SPEECH_LOAD_TIMING=1 "$@" \
    /usr/bin/time -v -o $out/time.txt \
    python3 $SC/gen.py $tag --binary $BIN --seeds 1 --only $ONLY > $out/gen.log 2>&1
  echo "rc=$?" > $out/rc.txt
  kill $VM 2>/dev/null
  chown -R $U:$U $out
  echo "$tag: $(cat $out/rc.txt) $(tail -1 $out/gen.log)"
done
