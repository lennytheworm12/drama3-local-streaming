# Step 1 of the VRAM plan: the device memory each switch frees (one take, one stream, every expert on the CPU), then
# teacher-forced KL of the half-precision caches against float32 on the recorded trajectories.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-35B-A3B-v3-Q4_K.gguf"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_GPU_EXPERT_LAYERS = "0"
$sw = @("SPEECH_KV_F16", "SPEECH_MAX_PROMPT_ROWS", "SPEECH_MAX_FRAMES", "SPEECH_EMBD_ON_CPU")
$runs = @(
  @{tag = "vr-base"; set = @{}},
  @{tag = "vr-kv16"; set = @{SPEECH_KV_F16 = "1"}},
  @{tag = "vr-kv16-rows"; set = @{SPEECH_KV_F16 = "1"; SPEECH_MAX_PROMPT_ROWS = "2048"; SPEECH_MAX_FRAMES = "1024"}},
  @{tag = "vr-all"; set = @{SPEECH_KV_F16 = "1"; SPEECH_MAX_PROMPT_ROWS = "2048"; SPEECH_MAX_FRAMES = "1024"; SPEECH_EMBD_ON_CPU = "1"}}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  foreach ($k in $r.set.Keys) { Set-Item "Env:$k" $r.set[$k] }
  & $py $tp $r.tag --binary $bin --model $m --streams 1 --only s01,s02 --seeds 1 --out "$w\runs" 2>&1 | Select-Object -Last 1
}
foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
"VRAM-DONE"
