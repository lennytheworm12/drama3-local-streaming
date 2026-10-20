# Throughput with several streams: 10 sentences x 2 seeds = 20 takes, submitted at once. Fused decoder, fread.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
Remove-Item Env:SPEECH_STEP_TIMING -ErrorAction SilentlyContinue
$runs = @(
  @{tag = "st1-cap4"; streams = 1; cap = "4"},
  @{tag = "st2-cap1"; streams = 2; cap = "1"},
  @{tag = "st2-cap0"; streams = 2; cap = "0"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_GPU_EXPERT_LAYERS = $r.cap
  & $py $tp $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams $r.streams --out "$w\runs" 2>&1 | Select-Object -Last 2
}
"STREAMS-DONE"
