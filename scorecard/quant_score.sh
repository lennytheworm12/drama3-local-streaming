#!/bin/bash
# Experiment 5 scorecards: each quant variant on the 20 sentences, seeds 1-2, mmap, with step timing; then ASR + UTMOS.
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
export SPEECH_MIXED_OK=1
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
R=$HOME/drama3/scorecard-runs
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
SENT=s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20
for v in ctl-q4k exps-iq4xs exps-q3k exps-iq3s exps-q2k; do
  m=$HOME/models/Drama-$v.gguf
  cat $m > /dev/null   # warm the page cache, so every variant starts alike
  SPEECH_MMAP=1 SPEECH_STEP_TIMING=1 python3 $SC/gen.py q-$v --binary $BIN --model $m --seeds 1,2 --only $SENT > $R/q-$v.log 2>&1
  echo "q-$v rc=$? $(grep -h 'computes the experts' $R/q-$v/worker.stderr.log | head -1 | cut -c1-90)"
done
for v in ctl-q4k exps-iq4xs exps-q3k exps-iq3s exps-q2k; do python3 $SC/asr.py $R/q-$v > $R/q-$v/asr.log 2>&1; done
python3 $SC/score.py $R/q-ctl-q4k $R/q-exps-iq4xs $R/q-exps-q3k $R/q-exps-iq3s $R/q-exps-q2k > $R/score-quant.md 2>&1
python3 /mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard/tools/steps.py $R/q-*/ >> $R/score-quant.md
cd $SC && ~/drama3/venv/bin/python mos.py $R/q-ctl-q4k $R/q-exps-iq4xs $R/q-exps-q3k $R/q-exps-iq3s $R/q-exps-q2k 2>/dev/null | grep '^|' >> $R/score-quant.md
echo QUANT-SCORE-DONE
