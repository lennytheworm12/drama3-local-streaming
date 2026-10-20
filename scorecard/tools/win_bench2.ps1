# Native Windows Vulkan runs of the patched build: 20 sentences, seed 1. Run with WSL shut down so RAM is free.
$ErrorActionPreference = "Continue"
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$out = "$w\runs"
$only = "s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20"
$env:SPEECH_MIXED_OK = "1"
$env:SPEECH_STEP_TIMING = "1"
$runs = @(
  @{tag = "vkp-q2k-fread"; model = "Drama-exps-q2k.gguf"; mmap = "0"},
  @{tag = "vkp-q4k-mmap2";  model = "Drama-35B-A3B-v3-Q4_K.gguf"; mmap = "1"},
  @{tag = "vkp-q2k-mmap2";  model = "Drama-exps-q2k.gguf";       mmap = "1"}
)
foreach ($r in $runs) {
  $env:SPEECH_MMAP = $r.mmap
  & $py $gen $r.tag --binary $bin --model "$w\$($r.model)" --out $out --seeds 1 --only $only *> "$out\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
"WIN-BENCH-DONE"
