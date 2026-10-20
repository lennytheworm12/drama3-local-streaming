# ggml Vulkan switches against the current best (fused decoder, fread, 4 GPU expert layers): Q4_K, 5 sentences, seed 1.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$only = "s04,s06,s11,s14,s19"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_STEP_TIMING = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_GPU_EXPERT_LAYERS = "4"; $env:SPEECH_FUSED_DECODER = "1"
$knobs = @("GGML_VK_FORCE_MMVQ", "GGML_VK_ASYNC_USE_TRANSFER_QUEUE", "GGML_VK_MAX_NODES_PER_SUBMIT", "GGML_VK_DISABLE_FUSION")
$runs = @(
  @{tag = "vk-base"; set = @{}},
  @{tag = "vk-mmvq"; set = @{GGML_VK_FORCE_MMVQ = "1"}},
  @{tag = "vk-xferq"; set = @{GGML_VK_ASYNC_USE_TRANSFER_QUEUE = "1"}},
  @{tag = "vk-nodes1000"; set = @{GGML_VK_MAX_NODES_PER_SUBMIT = "1000"}},
  @{tag = "vk-nofusion"; set = @{GGML_VK_DISABLE_FUSION = "1"}}
)
$tags = @()
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  foreach ($k in $knobs) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  foreach ($k in $r.set.Keys) { Set-Item "Env:$k" $r.set[$k] }
  & $py $gen $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --out "$w\runs" --seeds 1 --only $only *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
  $tags += $r.tag
}
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_summary.py @tags
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_steps.py @tags
"VKENV-DONE"
