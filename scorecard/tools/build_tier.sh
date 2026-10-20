export PATH=/usr/local/cuda/bin:$HOME/.local/bin:$PATH
cd ~/drama3/speech.cpp-exp
cmake -B build-tier -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release > build-tier-config.log 2>&1 || { tail -20 build-tier-config.log; exit 1; }
nice cmake --build build-tier --config Release -j 12 --target speech-cli > build-tier.log 2>&1 || nice cmake --build build-tier --config Release -j 12 >> build-tier.log 2>&1
echo "build rc=$?"; grep -E ' error|error:' build-tier.log | head -20; ls -l build-tier/speech
