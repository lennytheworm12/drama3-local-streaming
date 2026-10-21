@echo off
rem Builds the patched speech.cpp (src\speech.cpp-exp) natively on Windows with Vulkan, into build-vk4.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set VULKAN_SDK=C:\VulkanSDK\1.4.363.0
set PATH=%VULKAN_SDK%\Bin;%PATH%
cd /d C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp || exit /b 1
cmake -B build-vk4 -G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release > build-vk4-config.log 2>&1 || (type build-vk4-config.log & exit /b 1)
cmake --build build-vk4 --config Release -j 12 > build-vk4.log 2>&1
set RC=%ERRORLEVEL%
echo build rc=%RC%
findstr /i /c:" error " /c:"error C" /c:"fatal" build-vk4.log
dir build-vk4\speech.exe
exit /b %RC%
