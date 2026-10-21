# First look at the native CUDA build: per-frame time against Vulkan on the same text, then teacher-forced KL.
$env:PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin;C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin\x64;" + $env:PATH
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$m   = "C:\Users\bphan\PersonalProjects\drama3-local\win\Drama-35B-A3B-v3-Q4_K.gguf"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$o   = "$w\runs\cuda"; New-Item -ItemType Directory -Force $o | Out-Null
$bins = @{vk = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"; cu = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-cu\speech.exe"}
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_STEP_TIMING = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"
$text = "In 1969, two astronauts walked on the moon while millions watched on grainy televisions. The landing took years of planning, thousands of engineers, and a computer with less memory than a modern calculator."
foreach ($layers in @("4", "8")) {
  $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = $layers
  foreach ($b in @("vk", "cu")) {
    $t0 = Get-Date
    & $bins[$b] tts $m --voice none --seed 5 -o "$o\$b-l$layers.wav" $text 2> "$o\$b-l$layers.log"
    $line = (Select-String -Path "$o\$b-l$layers.log" -Pattern "per frame ms" | Select-Object -Last 1).Line
    "$b layers=$layers rc=$LASTEXITCODE $([int]((Get-Date) - $t0).TotalSeconds) s  $line"
  }
}
Get-Content "$o\cu-l4.log" -Tail 4
"CUDAFIRST-DONE"
