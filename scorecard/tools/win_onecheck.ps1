# SPEECH_ONE_GRAPH must give the same take as the separate graphs (fused decoder both times).
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$m   = "C:\Users\bphan\PersonalProjects\drama3-local\win\Drama-35B-A3B-v3-Q4_K.gguf"
$o   = "C:\Users\bphan\PersonalProjects\drama3-local\win\runs\onecheck"
New-Item -ItemType Directory -Force $o | Out-Null
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"; $env:SPEECH_STEP_TIMING = "1"
$text = "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets."
foreach ($one in @("0", "1")) {
  $env:SPEECH_ONE_GRAPH = $one
  $t0 = Get-Date
  & $bin tts $m --voice none --seed 3 -o "$o\one$one.wav" $text 2> "$o\one$one.log"
  "one=$one rc=$LASTEXITCODE $([int]((Get-Date) - $t0).TotalSeconds) s"
  Select-String -Path "$o\one$one.log" -Pattern "per frame" | ForEach-Object { "  " + $_.Line }
}
(Get-FileHash "$o\one0.wav").Hash; (Get-FileHash "$o\one1.wav").Hash
"ONECHECK-DONE"
