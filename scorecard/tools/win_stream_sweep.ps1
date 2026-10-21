# SSD streaming of the CPU layers' routed experts under total RAM caps of 12, 10 and 8 GB (the cache gets the cap less
# the process's 1.8 GB without its experts), each step added to the last: LRU with synchronous reads, then pinned hot
# experts, overlapped reads, the contiguous layout, prefetch. 10 takes each, one stream, 5 GPU expert layers; every
# take's WAV must equal the RAM run's.
$py  = "C:\Users\bphan\flux3-klein\ComfyUI_windows_portable\python_embeded\python.exe"
$tp  = "C:\Users\bphan\PersonalProjects\drama3-local\scorecard\tp.py"
$bin = "C:\Users\bphan\PersonalProjects\drama3-local\src\speech.cpp-exp\build-vk3\speech.exe"
$w   = "C:\Users\bphan\PersonalProjects\drama3-local\win"
$m   = "$w\Drama-imx2-mix.gguf"
$env:SPEECH_MIXED_OK = "1"; $env:SPEECH_MMAP = "0"; $env:SPEECH_FUSED_DECODER = "1"; $env:SPEECH_GPU_EXPERT_LAYERS_EXACT = "5"
$env:SPEECH_KV_F16 = "1"; $env:SPEECH_MAX_PROMPT_ROWS = "2048"; $env:SPEECH_MAX_FRAMES = "1024"; $env:SPEECH_EMBD_ON_CPU = "1"; $env:SPEECH_FLASH_ATTN = "1"; $env:SPEECH_SCHED_PINNED = "1"
$env:SPEECH_STREAM_IMATRIX = "$w\imatrix-en2.simx"
$sw = @("SPEECH_STREAM_MB", "SPEECH_STREAM_PIN", "SPEECH_STREAM_IO", "SPEECH_STREAM_FILE", "SPEECH_STREAM_PREFETCH")
$steps = @(
  @{tag = "lru"; set = @{SPEECH_STREAM_IO = "sync"}},
  @{tag = "pin"; set = @{SPEECH_STREAM_IO = "sync"; SPEECH_STREAM_PIN = "0.6"}},
  @{tag = "ovl"; set = @{SPEECH_STREAM_IO = "overlapped"; SPEECH_STREAM_PIN = "0.6"}},
  @{tag = "cont"; set = @{SPEECH_STREAM_IO = "overlapped"; SPEECH_STREAM_PIN = "0.6"; SPEECH_STREAM_FILE = "$w\Drama-imx2-mix.experts"}},
  @{tag = "pref"; set = @{SPEECH_STREAM_IO = "overlapped"; SPEECH_STREAM_PIN = "0.6"; SPEECH_STREAM_FILE = "$w\Drama-imx2-mix.experts"; SPEECH_STREAM_PREFETCH = "1"}}
)
$caps = @(@{gb = 12; mb = "10400"}, @{gb = 10; mb = "8350"}, @{gb = 8; mb = "6300"})
$runs = @(@{tag = "st-ram"; set = @{}})
foreach ($c in $caps) { foreach ($s in $steps) { $set = $s.set.Clone(); $set["SPEECH_STREAM_MB"] = $c.mb; $runs += @{tag = "st-$($c.gb)g-$($s.tag)"; set = $set} } }
foreach ($r in $runs) {
  if ($args.Count -gt 0 -and -not ($r.tag -like $args[0])) { continue }
  while (Get-Process speech -ErrorAction SilentlyContinue) { Start-Sleep 15 }
  foreach ($k in $sw) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  foreach ($k in $r.set.Keys) { Set-Item "Env:$k" $r.set[$k] }
  $line = & $py $tp $r.tag --binary $bin --model $m --streams 1 --seeds 1 --out "$w\runs" 2>&1 | Select-Object -Last 1
  $stat = (Get-Content "$w\runs\$($r.tag)\worker.stderr.log" | Select-String "hit rate").Line
  $same = "-"
  if ($r.tag -ne "st-ram") {
    $diff = 0
    foreach ($f in Get-ChildItem "$w\runs\st-ram\*.wav") {
      if ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash "$w\runs\$($r.tag)\$($f.Name)").Hash) { $diff++ }
    }
    $same = if ($diff -eq 0) { "all takes identical" } else { "$diff takes DIFFER" }
  }
  "$line"
  "  $stat"
  "  $same"
}
"STREAMSWEEP-DONE"
