#!/bin/bash
# Writes the hot-expert sidecars (30% of each layer's experts at Q6_K, then at Q5_K) and copies them to win\.
set -u
W=/mnt/c/Users/bphan/PersonalProjects/drama3-local/win
BIN=$HOME/drama3/speech.cpp-exp/build-cpu2/hotx
for t in q6_K q5_K; do
  out=$HOME/models/Drama-hot30-$t.gguf
  t0=$(date +%s)
  $BIN $HOME/models/Drama-35B-A3B-v3-F16.gguf $W/imatrix-en2.simx $out.tmp 0.3 $t > $HOME/drama3/fidelity/hotx-$t.log 2>&1 && mv $out.tmp $out
  echo "$t rc=$? $(( $(date +%s) - t0 )) s $(stat -c %s $out 2>/dev/null) bytes"
  tail -2 $HOME/drama3/fidelity/hotx-$t.log
  cp $out $W/ && echo "$t copied"
done
echo HOTX-DONE
