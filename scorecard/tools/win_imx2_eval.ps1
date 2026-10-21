# Teacher-forced KL against F16 of the published Q4_K and the English-imatrix Q4_K, on the 6 held-out trajectories.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$f   = "$w\fidelity"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "4"
foreach ($k in @("SPEECH_FUSED_DECODER", "SPEECH_IMATRIX_OUT", "SPEECH_KV_F16", "SPEECH_FLASH_ATTN", "SPEECH_STREAMS", "SPEECH_MAX_PROMPT_ROWS", "SPEECH_MAX_FRAMES", "SPEECH_EMBD_ON_CPU")) {
  Remove-Item "Env:$k" -ErrorAction SilentlyContinue
}
$texts = @("In 1969, two astronauts walked on the moon while millions watched on grainy televisions.",
           "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.") +
         (Get-Content "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\fidelity-extra.txt")
$models = @{imx2 = "$w\Drama-imx2-q4k.gguf"; mix = "$w\Drama-imx2-mix.gguf"}
foreach ($tag in @("imx2", "mix")) {
  for ($i = 0; $i -lt $texts.Count; $i++) {
    $out = "$f\e-$tag-$i.logits"
    Remove-Item $out -ErrorAction SilentlyContinue
    $env:SPEECH_FORCE = "$f\rec-$i.bin"; $env:SPEECH_LOGITS = $out
    & $bin tts $models[$tag] --voice none --seed 1 -o "$f\e-$tag-$i.wav" $texts[$i] 2> "$f\e-$tag-$i.log"
    Remove-Item Env:SPEECH_FORCE, Env:SPEECH_LOGITS
    "$tag $i rc=$LASTEXITCODE"
  }
}
& $py "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\kl_table.py" $f --refs f16 --variants e-pub e-imx e-imx2 e-mix --n $texts.Count
"IMX2EVAL-DONE"
