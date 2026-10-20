#!/bin/bash
set -e
mkdir -p ~/drama3/fio && cd ~/drama3/fio
fio --name=prep --filename=fiotest --size=20G --rw=write --bs=16M --direct=1 --ioengine=libaio --iodepth=8 --output-format=terse >/dev/null
for bs in 4M 16M; do for qd in 1 8; do
  r=$(fio --name=r --filename=fiotest --size=20G --rw=randread --bs=$bs --direct=1 --ioengine=libaio --iodepth=$qd --runtime=30 --time_based --output-format=json | python3 -c 'import json,sys;j=json.load(sys.stdin)["jobs"][0]["read"];print(round(j["bw_bytes"]/1e6),"MB/s", "lat_ms_mean", round(j["clat_ns"]["mean"]/1e6,1))')
  echo "bs=$bs iodepth=$qd: $r"
done; done
rm -f fiotest
