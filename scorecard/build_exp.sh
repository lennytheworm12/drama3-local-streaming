#!/bin/bash
# Builds the experiment branch (~/drama3/speech.cpp-exp) with CUDA for the RTX 4060 Ti (SM89).
set -u
export PATH=/usr/local/cuda/bin:$HOME/.local/bin:$PATH
cd ~/drama3/speech.cpp-exp
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release > build-config.log 2>&1 || { echo "configure failed"; tail -20 build-config.log; exit 1; }
cmake --build build --config Release -j 12 > build.log 2>&1
rc=$?
echo "build rc=$rc"
grep -E 'error|Error' build.log | head -20
ls -l build/speech
exit $rc
