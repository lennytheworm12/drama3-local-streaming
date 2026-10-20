# Fused audio decoder (SPEECH_FUSED_DECODER=1): (1) exactness check with top_k=1 (argmax, so both paths must agree),
# (2) speed on 10 sentences with normal sampling. Q4_K, fread, 4 GPU expert layers.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-35B-A3B-v3-Q4_K.gguf"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_STEP_TIMING = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"
$env:SPEECH_DECODER_TIMING = "1"; $env:SPEECH_DECODER_ON_CPU = "0"
$runs = @(
  @{tag = "fz-greedy-off"; fused = "0"; only = "s04,s11"; opt = "top_k=1"},
  @{tag = "fz-greedy-on";  fused = "1"; only = "s04,s11"; opt = "top_k=1"},
  @{tag = "fz-on";         fused = "1"; only = "s01,s02,s03,s04,s06,s07,s10,s11,s14,s19"; opt = ""}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_FUSED_DECODER = $r.fused
  $extra = @(); if ($r.opt) { $extra = @("--opt", $r.opt) }
  & $py $gen $r.tag --binary $bin --model $m --out "$w\runs" --seeds 1 --only $r.only @extra *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
foreach ($s in "s04", "s11") {
  $a = (Get-FileHash "$w\runs\fz-greedy-off\$s-s1.wav").Hash; $b = (Get-FileHash "$w\runs\fz-greedy-on\$s-s1.wav").Hash
  "$s greedy identical: $($a -eq $b)"
}
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_summary.py dec-trace fz-on
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_steps.py dec-trace fz-on
Select-String -Path "$w\runs\fz-on\worker.stderr.log" -Pattern "decoder-timing" | Select-Object -Last 1 | ForEach-Object { $_.Line }
"FUSED-DONE"
