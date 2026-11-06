#!/bin/bash
# Prove what the volume actually delivers right now, independent of Weaviate.
# Usage: fio-calibrate.sh <phase>     -> /data/results/<phase>/fio-*.json + one summary line
set -euo pipefail
source /etc/ebs-blog.env
DATA_DEV="$(basename "$(findmnt -no SOURCE /data)")"   # NVMe names can change across reboots; trust the mount
PHASE="${1:?phase}"
OUT="/data/results/$PHASE"; mkdir -p "$OUT"
TEST=/data/fio.test

# 4 KiB random reads, deep queue: measures the IOPS ceiling.
fio --name=randread4k --filename=$TEST --size=20G --rw=randread --bs=4k --direct=1 \
    --ioengine=libaio --iodepth=64 --numjobs=4 --runtime=60 --time_based --group_reporting \
    --output-format=json --output="$OUT/fio-randread-4k.json" >/dev/null

# 1 MiB sequential reads: measures the throughput ceiling.
fio --name=seqread1m --filename=$TEST --size=20G --rw=read --bs=1M --direct=1 \
    --ioengine=libaio --iodepth=16 --numjobs=2 --runtime=30 --time_based --group_reporting \
    --output-format=json --output="$OUT/fio-seqread-1m.json" >/dev/null

rm -f $TEST
sync; echo 3 > /proc/sys/vm/drop_caches

IOPS=$(jq '.jobs[0].read.iops | floor' "$OUT/fio-randread-4k.json")
LAT_US=$(jq '.jobs[0].read.clat_ns.mean / 1000 | floor' "$OUT/fio-randread-4k.json")
MBPS=$(jq '.jobs[0].read.bw_bytes / 1048576 | floor' "$OUT/fio-seqread-1m.json")
echo "phase=$PHASE randread_4k_iops=$IOPS randread_4k_mean_lat_us=$LAT_US seqread_1m_mib_s=$MBPS" | tee "$OUT/fio-summary.txt"
