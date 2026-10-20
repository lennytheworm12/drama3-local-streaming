#!/bin/bash
# Experiment 5 (mixed-precision quants) and the KL fidelity test. Run as the normal user.
#   quant_fid.sh quant      make the variants from the F16 file
#   quant_fid.sh record     Q4_K records trajectories (and its own logits) for the fidelity sentences
#   quant_fid.sh f16        F16 (CPU, mmap) replays them: the reference logits
#   quant_fid.sh variants   every variant (and Q4_K itself, the self-check) replays them; KL against F16
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
export SPEECH_MIXED_OK=1   # the mixed files name their base type (Q4_K) while their experts hold most bytes
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
M=$HOME/models
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
FID=$HOME/drama3/fidelity; mkdir -p $FID
F16=$M/Drama-35B-A3B-v3-F16.gguf
Q4=$M/Drama-35B-A3B-v3-Q4_K.gguf
# name: rules (base type q4_k for every variant, so only the routed experts' type changes)
declare -A RULES=([ctl-q4k]="" [exps-iq4xs]="_exps=iq4_xs" [exps-q3k]="_exps=q3_K" [exps-iq3s]="_exps=iq3_s" [exps-q2k]="_exps=q2_K")
VARIANTS="ctl-q4k exps-iq4xs exps-q3k exps-iq3s exps-q2k"
TEXTS=("In 1969, two astronauts walked on the moon while millions watched on grainy televisions." \
       "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.")

case $1 in
quant)
  for v in $VARIANTS; do
    out=$M/Drama-$v.gguf
    [ -f $out ] && { echo "$v exists"; continue; }
    t0=$(date +%s)
    SPEECH_QUANT_FROM_F16=1 SPEECH_QUANT_RULES="${RULES[$v]}" $BIN quantize $F16 $out.tmp --type q4_k > $FID/quant-$v.log 2>&1 \
      && mv $out.tmp $out
    echo "$v rc=$? $(( $(date +%s) - t0 )) s $(ls -l $out 2>/dev/null | awk '{print $5}') bytes"
  done ;;
record)
  for i in "${!TEXTS[@]}"; do
    rm -f $FID/rec-$i.bin $FID/q4-$i.logits
    SPEECH_MMAP=1 SPEECH_RECORD=$FID/rec-$i.bin SPEECH_LOGITS=$FID/q4-$i.logits \
      $BIN tts $Q4 --voice none --seed 1 -o $FID/rec-$i.wav "${TEXTS[$i]}" > $FID/record-$i.log 2>&1
    echo "record $i rc=$? frames=$(( $(stat -c %s $FID/rec-$i.bin) / 44 ))"
  done ;;
f16)
  for i in "${!TEXTS[@]}"; do
    rm -f $FID/f16-$i.logits
    t0=$(date +%s)
    SPEECH_MMAP=1 SPEECH_FORCE=$FID/rec-$i.bin SPEECH_LOGITS=$FID/f16-$i.logits SPEECH_STEP_TIMING=1 \
      $BIN tts $F16 --device cpu --threads 8 --voice none --seed 1 -o $FID/f16-$i.wav "${TEXTS[$i]}" > $FID/f16-$i.log 2>&1
    echo "f16 $i rc=$? $(( $(date +%s) - t0 )) s"
  done ;;
variants)
  for v in q4-self $VARIANTS; do
    model=$M/Drama-$v.gguf; [ $v = q4-self ] && model=$Q4
    [ -f $model ] || { echo "$v missing"; continue; }
    for i in "${!TEXTS[@]}"; do
      rm -f $FID/$v-$i.logits
      SPEECH_MMAP=1 SPEECH_FORCE=$FID/rec-$i.bin SPEECH_LOGITS=$FID/$v-$i.logits \
        $BIN tts $model --voice none --seed 1 -o $FID/$v-$i.wav "${TEXTS[$i]}" > $FID/$v-$i.log 2>&1
      echo "== $v sentence $i rc=$? vs F16"
      python3 $SC/fidelity.py $FID/f16-$i.logits $FID/$v-$i.logits | grep -E 'main|all codebooks|unmatched'
      [ $v = q4-self ] && { echo "self-check vs recording run:"; python3 $SC/fidelity.py $FID/q4-$i.logits $FID/$v-$i.logits | grep -E 'main|all codebooks|unmatched'; }
    done
  done ;;
esac
