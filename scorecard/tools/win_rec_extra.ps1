# Records 4 more held-out fidelity trajectories with the published Q4_K (60 frames each, rec-2..5.bin), for F16 to replay.
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$m   = "C:\Users\bphan\PersonalProjects\drama3-local\win\Drama-35B-A3B-v3-Q4_K.gguf"
$f   = "C:\Users\bphan\PersonalProjects\drama3-local\win\fidelity"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "4"
Remove-Item Env:SPEECH_FUSED_DECODER, Env:SPEECH_IMATRIX_OUT, Env:SPEECH_KV_F16, Env:SPEECH_FLASH_ATTN -ErrorAction SilentlyContinue
$texts = Get-Content "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\fidelity-extra.txt"
for ($i = 0; $i -lt $texts.Count; $i++) {
  $n = $i + 2
  Remove-Item "$f\rec-$n.bin" -ErrorAction SilentlyContinue
  $env:SPEECH_RECORD = "$f\rec-$n.bin"
  & $bin tts $m --voice none --seed 1 -o "$f\rec-$n.wav" $texts[$i] 2> "$f\record-$n.log"
  Remove-Item Env:SPEECH_RECORD
  # 60 frames of 11 int32s: the main token and 10 codes.
  $bytes = [System.IO.File]::ReadAllBytes("$f\rec-$n.bin")
  $keep = [Math]::Min($bytes.Length, 60 * 44)
  [System.IO.File]::WriteAllBytes("$f\rec-$n.bin", $bytes[0..($keep - 1)])
  "rec $n rc=$LASTEXITCODE frames=$($keep / 44)"
}
"REC-DONE"
