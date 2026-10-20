# Audio decoder on the CPU (SPEECH_DECODER_ON_CPU=1) against the GPU decoder: Q4_K, fread, 10 sentences, seed 1.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$only = "s01,s02,s03,s04,s06,s07,s10,s11,s14,s19"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_STEP_TIMING = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_DECODER_TIMING = "1"
foreach ($r in @(@{tag = "dec-cpu-cap4"; cap = "4"}, @{tag = "dec-cpu-cap5"; cap = "5"})) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_GPU_EXPERT_LAYERS = $r.cap; $env:SPEECH_DECODER_ON_CPU = "1"
  & $py $gen $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --out "$w\runs" --seeds 1 --only $only *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_summary.py dec-trace dec-cpu-cap4 dec-cpu-cap5
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_steps.py dec-trace dec-cpu-cap4 dec-cpu-cap5
foreach ($t in "dec-cpu-cap4", "dec-cpu-cap5") { Select-String -Path "$w\runs\$t\worker.stderr.log" -Pattern "decoder-timing" | Select-Object -Last 1 | ForEach-Object { "$t $($_.Line)" } }
"DEC-DONE"
