# Per-frame time of SPEECH_ONE_GRAPH against separate graphs, alternating, on a longer text.
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$m   = "C:\Users\bphan\PersonalProjects\drama3-local\win\Drama-35B-A3B-v3-Q4_K.gguf"
$o   = "C:\Users\bphan\PersonalProjects\drama3-local\win\runs\onecheck"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"; $env:SPEECH_STEP_TIMING = "1"
$env:GGML_SCHED_TIMING = "1"; Remove-Item Env:GGML_SCHED_SPLITS -ErrorAction SilentlyContinue
$text = "In 1969, two astronauts walked on the moon while millions watched on grainy televisions. The landing took years of planning, thousands of engineers, and a computer with less memory than a modern calculator. Yet the most dangerous moment came in the final minutes, when alarms kept flashing and the fuel ran low."
foreach ($rep in 1..2) {
  foreach ($one in @("0", "1")) {
    $env:SPEECH_ONE_GRAPH = $one
    & $bin tts $m --voice none --seed 5 -o "$o\t$one-$rep.wav" $text 2> "$o\t$one-$rep.log"
    "one=$one rep=$rep"
    Select-String -Path "$o\t$one-$rep.log" -Pattern "per frame|sched-timing|graphs" | Select-Object -Last 3 | ForEach-Object { "  " + $_.Line }
  }
}
"ONETIME-DONE"
