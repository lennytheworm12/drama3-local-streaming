# Step 1 and 2 of the plan, throughput on 20 takes: the freed VRAM spent on more GPU expert layers or a third stream,
# then one graph a frame (SPEECH_ONE_GRAPH).
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$free = @{SPEECH_KV_F16 = "1"; SPEECH_MAX_PROMPT_ROWS = "2048"; SPEECH_MAX_FRAMES = "1024"; SPEECH_EMBD_ON_CPU = "1"}
$sw = @("SPEECH_KV_F16", "SPEECH_MAX_PROMPT_ROWS", "SPEECH_MAX_FRAMES", "SPEECH_EMBD_ON_CPU", "SPEECH_ONE_GRAPH")
$runs = @(
  @{tag = "v2-st1-cap4-ref"; streams = 1; cap = "4"; threads = ""; free = $false; one = $false},
  @{tag = "v2-st1-cap6"; streams = 1; cap = "6"; threads = ""; free = $true; one = $false},
  @{tag = "v2-st1-cap8"; streams = 1; cap = "8"; threads = ""; free = $true; one = $false},
  @{tag = "v2-st2-cap0"; streams = 2; cap = "0"; threads = "4"; free = $true; one = $false},
  @{tag = "v2-st2-cap2"; streams = 2; cap = "2"; threads = "4"; free = $true; one = $false},
  @{tag = "v2-st2-cap4"; streams = 2; cap = "4"; threads = "4"; free = $true; one = $false},
  @{tag = "v2-st3-cap0-t3"; streams = 3; cap = "0"; threads = "3"; free = $true; one = $false},
  @{tag = "v2-st1-cap8-one"; streams = 1; cap = "8"; threads = ""; free = $true; one = $true},
  @{tag = "v2-st2-cap0-one"; streams = 2; cap = "0"; threads = "4"; free = $true; one = $true}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  if ($r.free) { foreach ($k in $free.Keys) { Set-Item "Env:$k" $free[$k] } }
  if ($r.one) { $env:SPEECH_ONE_GRAPH = "1" }
  $env:SPEECH_GPU_EXPERT_LAYERS = $r.cap
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
}
"VRAM2-DONE"
