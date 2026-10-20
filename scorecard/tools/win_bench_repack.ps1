# CPU_REPACK test on native Vulkan: the published Q4_K, 20 sentences, seed 1; repack against the mmap+prefetch baseline.
# Waits for any other speech.exe to exit first, so the GPU and RAM are not shared.
while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk2\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$only = "s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_STEP_TIMING = "1"
$runs = @(
  @{tag = "rp2-q4k-base";   mmap = "1"; repack = "0"},
  @{tag = "rp2-q4k-repack"; mmap = "0"; repack = "1"}
)
foreach ($r in $runs) {
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  $env:SPEECH_MMAP = $r.mmap; $env:SPEECH_CPU_REPACK = $r.repack
  & $py $gen $r.tag --binary $bin --model "$w\Drama-35B-A3B-v3-Q4_K.gguf" --out "$w\runs" --seeds 1 --only $only *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
& $py C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_summary.py vkp-q4k-mmap2 rp-q4k-base rp-q4k-repack rp2-q4k-base rp2-q4k-repack
"REPACK-DONE"
