#!/bin/bash
# Pin readahead and record the host state that matters for the measurement.
# Run as root on the server after every reboot and at the start of every phase.
# Usage: tune-disk.sh [phase]   (output is also written to /data/results/<phase>/host-state.txt)
set -euo pipefail
source /etc/ebs-blog.env
DATA_DEV="$(basename "$(findmnt -no SOURCE /data)")"   # NVMe names can change across reboots; trust the mount
PHASE="${1:-adhoc}"
OUT="/data/results/$PHASE"; mkdir -p "$OUT"

# Default readahead (128 KB) turns a 3 KB random rescore read into a 128 KB read via
# mmap fault-around, which would make the baseline look throughput-bound. Pin it small.
echo 16 > "/sys/block/$DATA_DEV/queue/read_ahead_kb"
swapoff -a || true

{
  echo "date: $(date -u +%FT%TZ)"
  echo "instance: $(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/instance-type)"
  echo "kernel: $(uname -r)"
  echo "data_dev: $DATA_DEV"
  echo "read_ahead_kb: $(cat /sys/block/$DATA_DEV/queue/read_ahead_kb)"
  echo "scheduler: $(cat /sys/block/$DATA_DEV/queue/scheduler)"
  echo "nr_requests: $(cat /sys/block/$DATA_DEV/queue/nr_requests)"
  echo "mount: $(findmnt -no SOURCE,FSTYPE,OPTIONS /data)"
  echo "swap: $(swapon --show || echo none)"
  echo "cgroup: $(stat -fc %T /sys/fs/cgroup) controllers=[$(cat /sys/fs/cgroup/cgroup.controllers)]"
  echo "docker: $(docker version --format '{{.Server.Version}}') compose=$(docker compose version --short)"
  echo "mem_total_kb: $(grep MemTotal /proc/meminfo | awk '{print $2}')"
  echo "data_disk: ${DATA_DISK:-ebs} model=$(lsblk -dno MODEL /dev/$DATA_DEV 2>/dev/null | tr -s ' ') size=$(lsblk -dno SIZE /dev/$DATA_DEV 2>/dev/null)"
  if [ "${DATA_DISK:-ebs}" = "ebs" ]; then echo "volume: $(aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --query 'Volumes[0].[VolumeType,Size,Iops,Throughput]' --output text 2>/dev/null || echo 'aws cli unavailable')"; fi
} | tee "$OUT/host-state.txt"
