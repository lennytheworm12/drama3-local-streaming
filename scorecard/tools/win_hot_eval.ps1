# Hot experts at a higher type: KL against F16 on the 6 held-out trajectories, every expert layer on the CPU (so the
# sidecar covers all 40), for the mixed file alone and with each sidecar; then speed and RAM with narrate's settings.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$f   = "$w\fidelity"
$m   = "$w\Drama-imx2-mix.gguf"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "0"
foreach ($k in @("SPEECH_FUSED_DECODER", "SPEECH_IMATRIX_OUT", "SPEECH_KV_F16", "SPEECH_FLASH_ATTN", "SPEECH_STREAMS", "SPEECH_MAX_PROMPT_ROWS", "SPEECH_MAX_FRAMES", "SPEECH_EMBD_ON_CPU", "SPEECH_HOT_FILE", "SPEECH_SCHED_PINNED")) {
  Remove-Item "Env:$k" -ErrorAction SilentlyContinue
}
$texts = @("In 1969, two astronauts walked on the moon while millions watched on grainy televisions.",
           "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.") +
         (Get-Content "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\fidelity-extra.txt")
$vars = @(@{tag = "mix0"; hot = ""}, @{tag = "hot6"; hot = "$w\Drama-hot30-q6_K.gguf"}, @{tag = "hot5"; hot = "$w\Drama-hot30-q5_K.gguf"})
foreach ($v in $vars) {
  if ($v.hot) { $env:SPEECH_HOT_FILE = $v.hot } else { Remove-Item Env:SPEECH_HOT_FILE -ErrorAction SilentlyContinue }
  for ($i = 0; $i -lt $texts.Count; $i++) {
    $out = "$f\e-$($v.tag)-$i.logits"
    Remove-Item $out -ErrorAction SilentlyContinue
    $env:SPEECH_FORCE = "$f\rec-$i.bin"; $env:SPEECH_LOGITS = $out
    & $bin tts $m --voice none --seed 1 -o "$f\e-$($v.tag)-$i.wav" $texts[$i] 2> "$f\e-$($v.tag)-$i.log"
    Remove-Item Env:SPEECH_FORCE, Env:SPEECH_LOGITS
    "$($v.tag) $i rc=$LASTEXITCODE"
  }
}
Remove-Item Env:SPEECH_HOT_FILE -ErrorAction SilentlyContinue
& $py "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\kl_table.py" $f --refs f16 --variants e-pub e-mix e-mix0 e-hot6 e-hot5 --n $texts.Count
# Speed and RAM, narrate's settings.
$env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_SCHED_PINNED = "1"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"
$runs = @(
  @{tag = "hs-mix-st1"; hot = ""; streams = 1; threads = ""},
  @{tag = "hs-hot6-st1"; hot = "$w\Drama-hot30-q6_K.gguf"; streams = 1; threads = ""},
  @{tag = "hs-hot5-st1"; hot = "$w\Drama-hot30-q5_K.gguf"; streams = 1; threads = ""},
  @{tag = "hs-mix-st4"; hot = ""; streams = 4; threads = "2"},
  @{tag = "hs-hot6-st4"; hot = "$w\Drama-hot30-q6_K.gguf"; streams = 4; threads = "2"},
  @{tag = "hs-hot5-st4"; hot = "$w\Drama-hot30-q5_K.gguf"; streams = 4; threads = "2"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  if ($r.hot) { $env:SPEECH_HOT_FILE = $r.hot } else { Remove-Item Env:SPEECH_HOT_FILE -ErrorAction SilentlyContinue }
  $extra = @(); if ($r.threads) { $extra = @("--threads", $r.threads) }
  & $py $tp $r.tag --binary $bin --model $m --streams $r.streams @extra --out "$w\runs" 2>&1 | Select-Object -Last 1
  $ws = (Get-Content "$w\runs\$($r.tag)\worker.stderr.log" | Select-String "hot experts of").Line
  if ($ws) { "  $ws" }
}
"HOTEVAL-DONE"
