# With the freed VRAM and flash attention: single-stream expert layers placed exactly, and 2-4 streams.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"
$env:SPEECH_FLASH_ATTN = "1"
Remove-Item Env:SPEECH_GPU_EXPERT_LAYERS, Env:SPEECH_ONE_GRAPH, Env:SPEECH_FUSE_OPS -ErrorAction SilentlyContinue
$runs = @(
  @{tag = "v3-st1-l6"; streams = 1; layers = "6"; threads = ""},
  @{tag = "v3-st1-l8"; streams = 1; layers = "8"; threads = ""},
  @{tag = "v3-st2-l4-t4"; streams = 2; layers = "4"; threads = "4"},
  @{tag = "v3-st3-l0-t3"; streams = 3; layers = "0"; threads = "3"},
  @{tag = "v3-st3-l2-t3"; streams = 3; layers = "2"; threads = "3"},
  @{tag = "v3-st3-l0-t4"; streams = 3; layers = "0"; threads = "4"},
  @{tag = "v3-st4-l0-t2"; streams = 4; layers = "0"; threads = "2"},
  @{tag = "v3-st4-l0-t3"; streams = 4; layers = "0"; threads = "3"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = $r.layers
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
}
"V3-DONE"
