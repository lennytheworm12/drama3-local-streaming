# Teacher-forced KL of the half-precision caches against float32 on the recorded trajectories; the new binary with no
# switch must match the old full-*.logits exactly.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-35B-A3B-v3-Q4_K.gguf"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"
Remove-Item Env:SPEECH_MAX_PROMPT_ROWS, Env:SPEECH_MAX_FRAMES, Env:SPEECH_EMBD_ON_CPU -ErrorAction SilentlyContinue
$texts = @("In 1969, two astronauts walked on the moon while millions watched on grainy televisions.",
           "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.")
$f = "$w\fidelity"
$env:SPEECH_GPU_EXPERT_LAYERS = "4"; Remove-Item Env:SPEECH_FUSED_DECODER
for ($i = 0; $i -lt 2; $i++) {
  foreach ($v in @(@{tag = "same"; kv = "0"}, @{tag = "kv16"; kv = "1"})) {
    Remove-Item "$f\$($v.tag)-$i.logits" -ErrorAction SilentlyContinue
    $env:SPEECH_KV_F16 = $v.kv; $env:SPEECH_FORCE = "$f\rec-$i.bin"; $env:SPEECH_LOGITS = "$f\$($v.tag)-$i.logits"
    & $bin tts $m --voice none --seed 1 -o "$f\$($v.tag)-$i.wav" $texts[$i] 2> "$f\$($v.tag)-$i.log"
    "$($v.tag) $i rc=$LASTEXITCODE"
  }
}
Remove-Item Env:SPEECH_FORCE, Env:SPEECH_LOGITS, Env:SPEECH_KV_F16 -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 2; $i++) {
  foreach ($t in @("same", "kv16")) {
    "== sentence ${i}: $t against full"
    & $py -c "import sys; sys.path.insert(0, r'C:\Users\bphan\PersonalProjects\drama3-local\scorecard'); sys.argv=['f', r'$f\full-$i.logits', r'$f\$t-$i.logits']; import fidelity; fidelity.main()"
  }
}
"KVFID-DONE"
