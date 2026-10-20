# Self-speculation feasibility: logits of the full model and of the draft (SPEECH_SKIP_CPU_EXPERTS=1, the layers whose
# experts the CPU holds run their shared expert alone) replaying the same recorded frames; then acceptance and KL.
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$m   = "C:\Users\bphan\PersonalProjects\drama3-local\win\Drama-35B-A3B-v3-Q4_K.gguf"
$f   = "C:\Users\bphan\PersonalProjects\drama3-local\win\fidelity"
$texts = @("In 1969, two astronauts walked on the moon while millions watched on grainy televisions.",
           "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.")
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"
Remove-Item Env:SPEECH_STREAMS, Env:SPEECH_FUSED_DECODER -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 2; $i++) {
  foreach ($v in @(@{tag = "full"; skip = "0"}, @{tag = "draft"; skip = "1"})) {
    Remove-Item "$f\$($v.tag)-$i.logits" -ErrorAction SilentlyContinue
    $env:SPEECH_SKIP_CPU_EXPERTS = $v.skip; $env:SPEECH_FORCE = "$f\rec-$i.bin"; $env:SPEECH_LOGITS = "$f\$($v.tag)-$i.logits"
    $t0 = Get-Date
    & $bin tts $m --voice none --seed 1 -o "$f\$($v.tag)-$i.wav" $texts[$i] 2> "$f\$($v.tag)-$i.log"
    "$($v.tag) $i rc=$LASTEXITCODE $([int]((Get-Date) - $t0).TotalSeconds) s"
  }
}
Remove-Item Env:SPEECH_FORCE, Env:SPEECH_LOGITS, Env:SPEECH_SKIP_CPU_EXPERTS -ErrorAction SilentlyContinue
$py = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
for ($i = 0; $i -lt 2; $i++) {
  "== sentence ${i}: draft against full"
  & $py -c "import sys; sys.path.insert(0, r'C:\Users\bphan\PersonalProjects\drama3-local\scorecard'); sys.argv=['f', r'$f\full-$i.logits', r'$f\draft-$i.logits']; import fidelity; fidelity.main()"
}
"DRAFT-DONE"
