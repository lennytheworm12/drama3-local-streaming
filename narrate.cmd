@echo off
rem Narrate a text file with Drama 3 (native Vulkan, Q4_K, four takes at once). Usage: narrate.cmd script.txt [--takes 3]
rem Close WSL first (wsl --shutdown) if it is holding RAM; the model wants about 8 GB.
"C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe" "%~dp0narrate.py" %*
