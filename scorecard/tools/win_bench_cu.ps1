# The native CUDA build (build-cu) on the best Vulkan setups: throughput on 20 takes.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-cu\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin;C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3\bin\x64;" + $env:PATH
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"
$env:SPEECH_FLASH_ATTN = "1"
Remove-Item Env:SPEECH_GPU_EXPERT_LAYERS, Env:SPEECH_ONE_GRAPH, Env:SPEECH_FUSE_OPS, Env:SPEECH_STEP_TIMING -ErrorAction SilentlyContinue
$runs = @(
  @{tag = "cu-st1-l8"; streams = 1; layers = "8"; threads = ""},
  @{tag = "cu-st4-l0-t2"; streams = 4; layers = "0"; threads = "2"},
  @{tag = "cu-st3-l2-t3"; streams = 3; layers = "2"; threads = "3"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = $r.layers
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
}
"CU-DONE"
