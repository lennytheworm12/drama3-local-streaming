# Step 3: teacher-forced KL of flash attention (against the half-precision caches) and of the fusion-shaped graphs
# (against the plain build), then per-frame time and the Vulkan op profile of each.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-35B-A3B-v3-Q4_K.gguf"
$f   = "$w\fidelity"
$o   = "$w\runs\step3"
New-Item -ItemType Directory -Force $o | Out-Null
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"
$sw = @("SPEECH_KV_F16", "SPEECH_FLASH_ATTN", "SPEECH_FUSE_OPS", "SPEECH_FUSED_DECODER", "SPEECH_STEP_TIMING", "GGML_VK_PERF_LOGGER")
$texts = @("In 1969, two astronauts walked on the moon while millions watched on grainy televisions.",
           "Most people overestimate how much they know about everyday objects like zippers, locks, and toilets.")
$fid = @(@{tag = "flash"; set = @{SPEECH_KV_F16 = "1"; SPEECH_FLASH_ATTN = "1"}; ref = "kv16"},
         @{tag = "fuse"; set = @{SPEECH_FUSE_OPS = "1"}; ref = "full"})
foreach ($v in $fid) {
  for ($i = 0; $i -lt 2; $i++) {
    foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    foreach ($k in $v.set.Keys) { Set-Item "Env:$k" $v.set[$k] }
    Remove-Item "$f\$($v.tag)-$i.logits" -ErrorAction SilentlyContinue
    $env:SPEECH_FORCE = "$f\rec-$i.bin"; $env:SPEECH_LOGITS = "$f\$($v.tag)-$i.logits"
    & $bin tts $m --voice none --seed 1 -o "$f\$($v.tag)-$i.wav" $texts[$i] 2> "$f\$($v.tag)-$i.log"
    "$($v.tag) $i rc=$LASTEXITCODE"
    Remove-Item Env:SPEECH_FORCE, Env:SPEECH_LOGITS
    & $py -c "import sys; sys.path.insert(0, r'C:\Users\bphan\PersonalProjects\drama3-local\scorecard'); sys.argv=['f', r'$f\$($v.ref)-$i.logits', r'$f\$($v.tag)-$i.logits']; import fidelity; fidelity.main()" | Select-Object -First 4
  }
}
$text = "In 1969, two astronauts walked on the moon while millions watched on grainy televisions. The landing took years of planning, thousands of engineers, and a computer with less memory than a modern calculator."
$prof = @(@{tag = "p-kv16"; set = @{SPEECH_KV_F16 = "1"}},
          @{tag = "p-flash"; set = @{SPEECH_KV_F16 = "1"; SPEECH_FLASH_ATTN = "1"}},
          @{tag = "p-fuse"; set = @{SPEECH_KV_F16 = "1"; SPEECH_FUSE_OPS = "1"}},
          @{tag = "p-both"; set = @{SPEECH_KV_F16 = "1"; SPEECH_FLASH_ATTN = "1"; SPEECH_FUSE_OPS = "1"}})
foreach ($perf in @("0", "1")) {
  foreach ($v in $prof) {
    foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    foreach ($k in $v.set.Keys) { Set-Item "Env:$k" $v.set[$k] }
    $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_STEP_TIMING = "1"
    if ($perf -eq "1") { $env:GGML_VK_PERF_LOGGER = "1" }
    $log = "$o\$($v.tag)-perf$perf.log"
    & $bin tts $m --voice none --seed 5 -o "$o\$($v.tag)-perf$perf.wav" $text 2> $log
    $line = (Select-String -Path $log -Pattern "per frame ms" | Select-Object -Last 1).Line
    "$($v.tag) perf=$perf rc=$LASTEXITCODE  $line"
    if ($perf -eq "1") {
      $frames = [int]([regex]::Match($line, "(\d+) frames").Groups[1].Value)
      & $py "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\vk_perf_sum.py" $log --frames $frames --top 25
    }
  }
}
foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
"STEP3-DONE"
