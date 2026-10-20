# Speed with the chosen voice file on native Vulkan (mmap + prefetch): Q4_K vs Q2_K, 20 sentences, seed 1.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$gen = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tools\win_gen.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$voice = "C:\Users\bphan\PersonalProjects\drama3-local\voices\v-clear-female-s4.voice.gguf"
$only = "s01,s02,s03,s04,s05,s06,s07,s08,s09,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "1"; $env:SPEECH_STEP_TIMING = "1"
foreach ($r in @(@{tag = "vkv-q4k"; model = "Drama-35B-A3B-v3-Q4_K.gguf"}, @{tag = "vkv-q2k"; model = "Drama-exps-q2k.gguf"})) {
  & $py $gen $r.tag --binary $bin --model "$w\$($r.model)" --out "$w\runs" --seeds 1 --only $only --add-voice "narrator=$voice" --opt voice=narrator *> "$w\runs\$($r.tag).log"
  "$($r.tag) rc=$LASTEXITCODE"
}
