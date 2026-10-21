# Overlap experiments: GGML_SCHED_EARLY (the device computes the shared expert while the CPU computes the routed ones)
# and SPEECH_SCHED_PINNED (the CPU side in pinned host memory). Same take with each (hash), per-frame time alternating,
# then 20-take throughput.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-35B-A3B-v3-Q4_K.gguf"
$o   = "$w\runs\overlap"; New-Item -ItemType Directory -Force $o | Out-Null
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"
$env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "6"
$sw = @("GGML_SCHED_EARLY", "SPEECH_SCHED_PINNED")
$cfg = @(@{tag = "base"; set = @{}}, @{tag = "early"; set = @{GGML_SCHED_EARLY = "1"}},
         @{tag = "pinned"; set = @{SPEECH_SCHED_PINNED = "1"}}, @{tag = "both"; set = @{GGML_SCHED_EARLY = "1"; SPEECH_SCHED_PINNED = "1"}})
$text = "In 1969, two astronauts walked on the moon while millions watched on grainy televisions. The landing took years of planning, thousands of engineers, and a computer with less memory than a modern calculator."
$env:SPEECH_STEP_TIMING = "1"
foreach ($rep in 1..2) {
  foreach ($c in $cfg) {
    foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    foreach ($k in $c.set.Keys) { Set-Item "Env:$k" $c.set[$k] }
    & $bin tts $m --voice none --seed 5 -o "$o\$($c.tag)-$rep.wav" $text 2> "$o\$($c.tag)-$rep.log"
    $line = (Select-String -Path "$o\$($c.tag)-$rep.log" -Pattern "per frame ms" | Select-Object -Last 1).Line
    "$($c.tag) rep=$rep rc=$LASTEXITCODE hash=$((Get-FileHash "$o\$($c.tag)-$rep.wav").Hash.Substring(0, 12))  $line"
  }
}
Remove-Item Env:SPEECH_STEP_TIMING
$runs = @(
  @{tag = "ov-st1-l6-base"; streams = 1; threads = ""; layers = "6"; set = @{}},
  @{tag = "ov-st1-l6-pinned"; streams = 1; threads = ""; layers = "6"; set = @{SPEECH_SCHED_PINNED = "1"}},
  @{tag = "ov-st4-l0-pinned"; streams = 4; threads = "2"; layers = "0"; set = @{SPEECH_SCHED_PINNED = "1"}},
  @{tag = "ov-st4-l0-base"; streams = 4; threads = "2"; layers = "0"; set = @{}}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  foreach ($k in $r.set.Keys) { Set-Item "Env:$k" $r.set[$k] }
  $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = $r.layers
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model $m --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
}
"OVERLAP-DONE"
