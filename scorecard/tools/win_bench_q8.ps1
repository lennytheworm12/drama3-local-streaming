# (1) Handoff trace (GGML_SCHED_TIMING) for Q4_K, fread, 4 GPU expert layers; (2) Q8_0 with mmap streaming and
# same-layer expert prefetch. 10 sentences, seed 1, native Vulkan (build-vk2).
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$only = "s01,s02,s03,s04,s06,s07,s10,s11,s14,s19"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_STEP_TIMING = "1"
$runs = @(
  @{tag = "trace-q4k-cap4"; model = "Drama-35B-A3B-v3-Q4_K.gguf"; mmap = "0"; cap = "4"; trace = "1"; pf = ""},
  @{tag = "q8-mmap-pf";     model = "Drama-35B-A3B-v3-Q8_0.gguf"; mmap = "1"; cap = "";  trace = ""; pf = "same"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_MMAP = $r.mmap; $env:SPEECH_GPU_EXPERT_LAYERS = $r.cap; $env:SPEECH_PREFETCH_EXPERTS = $r.pf
  if ($r.trace) { $env:GGML_SCHED_TIMING = "1" } else { Remove-Item Env:GGML_SCHED_TIMING -ErrorAction SilentlyContinue }
  & $py $gen $r.tag --binary $bin --model "$w\$($r.model)" --out "$w\runs" --seeds 1 --only $only *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_summary.py trace-q4k-cap4 q8-mmap-pf
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_steps.py trace-q4k-cap4 q8-mmap-pf
Select-String -Path "$w\runs\trace-q4k-cap4\worker.stderr.log" -Pattern "sched-timing" | Select-Object -Last 2 | ForEach-Object { $_.Line }
"Q8-DONE"
