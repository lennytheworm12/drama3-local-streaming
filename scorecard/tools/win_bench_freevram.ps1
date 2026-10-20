# Re-test of the VRAM-limited setups with the desktop's VRAM use low: throughput on 20 takes (10 sentences x 2 seeds).
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
Remove-Item Env:SPEECH_STEP_TIMING -ErrorAction SilentlyContinue
$runs = @(
  @{tag = "fv-st1-auto"; streams = 1; cap = ""; threads = ""},
  @{tag = "fv-st1-cap4"; streams = 1; cap = "4"; threads = ""},
  @{tag = "fv-st2-cap1-t4"; streams = 2; cap = "1"; threads = "4"},
  @{tag = "fv-st2-cap0-t4"; streams = 2; cap = "0"; threads = "4"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  if ($r.cap) { $env:SPEECH_GPU_EXPERT_LAYERS = $r.cap } else { Remove-Item Env:SPEECH_GPU_EXPERT_LAYERS -ErrorAction SilentlyContinue }
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
  Select-String -Path "$w\runs\$($r.tag)\worker.stderr.log" -Pattern "computes the experts of" | Select-Object -First 1 | ForEach-Object { "  " + $_.Line.Substring(0, 70) }
}
"FREEVRAM-DONE"
