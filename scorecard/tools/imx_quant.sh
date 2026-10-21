#!/bin/bash
# Quantizes the F16 file to Q4_K with the English importance matrix (SPEECH_QUANT_IMATRIX), then copies it to win\.
set -u
W=/mnt/c/Users/bphan/PersonalProjects/drama3-local/win
BIN=$HOME/drama3/speech.cpp-exp/build-cpu2/speech
out=$HOME/models/Drama-imx-q4k.gguf
t0=$(date +%s)
SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_IMATRIX=$W/imatrix-en.simx $BIN quantize $HOME/models/Drama-35B-A3B-v3-F16.gguf $out.tmp --type q4_k \
  > $HOME/drama3/fidelity/quant-imx.log 2>&1 && mv $out.tmp $out
echo "quantize rc=$? $(( $(date +%s) - t0 )) s $(stat -c %s $out 2>/dev/null) bytes"
grep -c "matrices weighted" $HOME/drama3/fidelity/quant-imx.log
grep "imatrix:" $HOME/drama3/fidelity/quant-imx.log | head -5
cp $out $W/Drama-imx-q4k.gguf && echo "copied"
echo IMXQ-DONE
