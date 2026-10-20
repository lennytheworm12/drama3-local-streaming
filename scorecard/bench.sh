#!/bin/bash
# Public benchmarks on the quant variants (mmap build, CUDA in WSL):
#   bench.sh ja   speech-bench's prompts/speak-ja-JP.json, 20 prompts x seeds 1-3, Qwen3-ASR 1.7B CER (voice none;
#                 upstream used a 12.8 s reference voice file, not published, so this is close but not identical)
#   bench.sh en   LibriSpeech test-clean, a fixed 100-utterance subset, seed 1, Qwen3-ASR 1.7B WER
set -u
export PATH=/usr/lib/wsl/lib:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin
export SPEECH_MIXED_OK=1 SPEECH_MMAP=1
SC=/mnt/c/Users/bphan/PersonalProjects/drama3-local/scorecard
R=$HOME/drama3/scorecard-runs
BIN=$HOME/drama3/speech.cpp-exp/build-tier/speech
declare -A MODEL=([q4k]=$HOME/models/Drama-35B-A3B-v3-Q4_K.gguf [q3k]=$HOME/models/Drama-exps-q3k.gguf
                  [q2k]=$HOME/models/Drama-exps-q2k.gguf [iq4xs]=$HOME/models/Drama-exps-iq4xs.gguf)
case $1 in
ja) CORPUS=$SC/corpus-speechbench-ja.jsonl; SEEDS=1,2,3; LANG=ja; VARS="q4k q3k q2k iq4xs" ;;
en) CORPUS=$SC/corpus-librispeech-100.jsonl; SEEDS=1; LANG=en; VARS="q4k q3k q2k" ;;
esac
runs=()
for v in $VARS; do
  tag=bench-$1-$v
  cat ${MODEL[$v]} > /dev/null
  python3 $SC/gen.py $tag --binary $BIN --model ${MODEL[$v]} --seeds $SEEDS --corpus $CORPUS > $R/$tag.log 2>&1
  echo "$tag gen rc=$?"
  runs+=($R/$tag)
done
for d in "${runs[@]}"; do python3 $SC/asr.py $d --language $LANG > $d/asr.log 2>&1; done
python3 $SC/score.py "${runs[@]}" > $R/score-bench-$1.md 2>&1
cd $SC && ~/drama3/venv/bin/python mos.py "${runs[@]}" 2>/dev/null | grep '^|' >> $R/score-bench-$1.md
echo "BENCH-$1-DONE"
