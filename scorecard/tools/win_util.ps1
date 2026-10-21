# What limits 4 streams: GPU and CPU utilization sampled every second during a 20-take run (Vulkan build-vk3).
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"
$env:SPEECH_FLASH_ATTN = "1"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "0"
$log = "$w\runs\util-st4.csv"
Remove-Item $log -ErrorAction SilentlyContinue
$smi = Start-Job -ScriptBlock { 1..800 | ForEach-Object { nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits; Start-Sleep -Milliseconds 400 } }
$cpu = Start-Job -ScriptBlock { 1..400 | ForEach-Object { (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue } }
& $py $tp util-st4 --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams 4 --threads 2 --out "$w\runs" 2>&1 | Select-Object -Last 1
Stop-Job $cpu, $smi
$g = Receive-Job $smi | Where-Object { $_ -match '^\d' } | ForEach-Object { [int]$_ }
$g -join ',' | Out-File -Encoding utf8 $log
$c = Receive-Job $cpu
"GPU util: samples $($g.Count), mean $([math]::Round(($g | Measure-Object -Average).Average,1))%, busy (>5%) samples mean $([math]::Round(($g | Where-Object { $_ -gt 5 } | Measure-Object -Average).Average,1))%"
"CPU util: samples $($c.Count), mean $([math]::Round(($c | Measure-Object -Average).Average,1))%"
"UTIL-DONE"
