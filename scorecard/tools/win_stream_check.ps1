# Expert streaming: the same take as with the experts in RAM (hash), first at a budget that holds every expert,
# then at a small one; with the stream's statistics.
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-imx2-mix.gguf"
$o   = "$w\runs\stream"; New-Item -ItemType Directory -Force $o | Out-Null
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "5"
$env:SPEECH_STEP_TIMING = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"; $env:SPEECH_SCHED_PINNED = "1"
$text = "In 1969, two astronauts walked on the moon while millions watched on grainy televisions."
foreach ($c in @(@{tag = "ram"; mb = ""; io = ""}, @{tag = "s4000-sync"; mb = "4000"; io = "sync"}, @{tag = "s4000-ovl"; mb = "4000"; io = "overlapped"})) {
  if ($c.mb) { $env:SPEECH_STREAM_MB = $c.mb; $env:SPEECH_STREAM_IO = $c.io } else { Remove-Item Env:SPEECH_STREAM_MB, Env:SPEECH_STREAM_IO -ErrorAction SilentlyContinue }
  $t0 = Get-Date
  & $bin tts $m --voice none --seed 3 -o "$o\$($c.tag).wav" $text 2> "$o\$($c.tag).log"
  "$($c.tag) rc=$LASTEXITCODE $([int]((Get-Date) - $t0).TotalSeconds) s hash=$((Get-FileHash "$o\$($c.tag).wav").Hash.Substring(0,12))"
  Select-String -Path "$o\$($c.tag).log" -Pattern "expert-stream|per frame" | ForEach-Object { "  " + $_.Line }
}
"STREAMCHECK-DONE"
