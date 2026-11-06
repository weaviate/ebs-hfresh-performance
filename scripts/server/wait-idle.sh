#!/bin/bash
# Block until Weaviate has nothing left to do in the background:
#   - async ingest queue drained (/v1/nodes vectorQueueLength == 0)
#   - HFresh analyze/split/merge/reassign pending ops == 0 for IDLE_MINUTES
#   - disk writes quiet (compactions finished) for WRITE_QUIET_MINUTES
# Usage: wait-idle.sh [IDLE_MINUTES=10] [WRITE_QUIET_MINUTES=5]
set -euo pipefail
source /etc/ebs-blog.env
DATA_DEV="$(basename "$(findmnt -no SOURCE /data)")"   # NVMe names can change across reboots; trust the mount
IDLE_MIN="${1:-10}"; WQ_MIN="${2:-5}"
idle_since=""; wq_since=""

pending() {
  curl -s localhost:2112/metrics \
    | awk '/^vector_index_pending_background_operations\{/ {s+=$NF} END {printf "%d", s}'
}
queue() {
  curl -s 'localhost:8080/v1/nodes?output=verbose' \
    | jq '[.nodes[].shards[]?.vectorQueueLength // 0] | add // 0'
}
writes() {
  iostat -d -y 5 1 "$DATA_DEV" | awk -v d="$DATA_DEV" '$1==d {print $4}'
}

while true; do
  now=$(date +%s); p=$(pending); q=$(queue); w=$(writes)
  if [ "$p" = "0" ] && [ "$q" = "0" ]; then idle_since="${idle_since:-$now}"; else idle_since=""; fi
  if awk -v w="$w" 'BEGIN{exit !(w < 5)}'; then wq_since="${wq_since:-$now}"; else wq_since=""; fi
  ii=$(( idle_since ? (now - idle_since)/60 : 0 )); wi=$(( wq_since ? (now - wq_since)/60 : 0 ))
  echo "$(date -u +%T) pending_bg_ops=$p vector_queue=$q writes_per_s=$w idle_min=$ii write_quiet_min=$wi"
  if [ "$ii" -ge "$IDLE_MIN" ] && [ "$wi" -ge "$WQ_MIN" ]; then echo "idle"; exit 0; fi
  sleep 55
done
