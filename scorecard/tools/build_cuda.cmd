@echo off
rem Builds the patched speech.cpp (src\speech.cpp-exp) natively on Windows with CUDA (sm_89, the RTX 4060 Ti), into build-cu.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3
set PATH=%CUDA_PATH%\bin;%PATH%
cd /d C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp || exit /b 1
cmake -B build-cu -G Ninja -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release > build-cu-config.log 2>&1 || (type build-cu-config.log & exit /b 1)
cmake --build build-cu --config Release -j 12 > build-cu.log 2>&1
set RC=%ERRORLEVEL%
echo build rc=%RC%
findstr /i /c:" error " /c:"error C" /c:"fatal" build-cu.log
dir build-cu\speech.exe
exit /b %RC%
