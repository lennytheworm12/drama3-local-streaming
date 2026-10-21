# The imatrix Q4_K on the 20-take throughput run (speed and runaways), then the cold open with the narrator voice,
# 2 takes per line, from both files for a blind A/B.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$root = "C:\Users\bphan\PersonalProjects\drama3-local"
$w   = "$root\win"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"
$env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "0"
& $py $tp imx-st4 --binary $bin --model "$w\Drama-imx-q4k.gguf" --streams 4 --threads 2 --out "$w\runs" 2>&1 | Select-Object -Last 1
foreach ($k in @("SPEECH_KV_F16", "SPEECH_MAX_PROMPT_ROWS", "SPEECH_MAX_FRAMES", "SPEECH_EMBD_ON_CPU", "SPEECH_FLASH_ATTN", "SPEECH_GPU_EXPERT_LAYERS_EXACT")) {
  Remove-Item "Env:$k" -ErrorAction SilentlyContinue
}
foreach ($v in @(@{tag = "pub"; m = "$w\Drama-35B-A3B-v3-Q4_K.gguf"}, @{tag = "imx"; m = "$w\Drama-imx-q4k.gguf"})) {
  & "$root\narrate.cmd" "$root\examples-cold-open.txt" --takes 2 --model $v.m --voice-file "$root\voices\v-clear-female-s4.voice.gguf" --out "$root\listening-r3\src-$($v.tag)" 2>&1 | Select-Object -Last 1
}
"IMXCHECK-DONE"
