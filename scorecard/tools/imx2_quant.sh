#!/bin/bash
# Round 2 of the English imatrix (text model, audio decoder and head): an all-Q4_K file, and a mix that keeps every
# tensor but the routed experts at Q6_K (token_embd and the head at Q8_0). Both from F16, then copied to win\.
set -u
W=/mnt/c/Users/bphan/PersonalProjects/drama3-local/win
BIN=$HOME/drama3/speech.cpp-exp/build-cpu2/speech
F16=$HOME/models/Drama-35B-A3B-v3-F16.gguf
declare -A RULES=([imx2-q4k]="" [imx2-mix]="_exps=q4_K,token_embd=q8_0,output=q8_0,blk.=q6_K,ad.=q6_K")
for v in imx2-q4k imx2-mix; do
  out=$HOME/models/Drama-$v.gguf
  t0=$(date +%s)
  SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_IMATRIX=$W/imatrix-en2.simx SPEECH_QUANT_RULES="${RULES[$v]}" \
    $BIN quantize $F16 $out.tmp --type q4_k > $HOME/drama3/fidelity/quant-$v.log 2>&1 && mv $out.tmp $out
  echo "$v rc=$? $(( $(date +%s) - t0 )) s $(stat -c %s $out 2>/dev/null) bytes"
  grep "weighted" $HOME/drama3/fidelity/quant-$v.log | grep -v "_exps" | head -4
  cp $out $W/Drama-$v.gguf && echo "$v copied"
done
echo IMX2Q-DONE
