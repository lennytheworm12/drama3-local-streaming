# Speed and VRAM of the mixed-precision imatrix file against the all-Q4_K one, with narrate's settings.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_SCHED_PINNED = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"
$runs = @(
  @{tag = "mx-q4-st1"; m = "Drama-imx-q4k.gguf"; streams = 1; layers = "6"; threads = ""},
  @{tag = "mx-mix-st1"; m = "Drama-imx2-mix.gguf"; streams = 1; layers = "6"; threads = ""},
  @{tag = "mx-q4-st4"; m = "Drama-imx-q4k.gguf"; streams = 4; layers = "0"; threads = "2"},
  @{tag = "mx-mix-st4"; m = "Drama-imx2-mix.gguf"; streams = 4; layers = "0"; threads = "2"},
  @{tag = "mx-mix-st3"; m = "Drama-imx2-mix.gguf"; streams = 3; layers = "0"; threads = "3"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = $r.layers
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model "$w\$($r.m)" --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
}
"MIXSPEED-DONE"
