#!/bin/bash
# Host-side telemetry during a benchmark run.
# Usage: capture.sh start <phase> <run>    |    capture.sh stop <phase> <run>
#   iostat -x 1 (JSON)                 -> iostat.json        (r/s, rMB/s, rareq-sz, r_await, aqu-sz, %util)
#   cgroup memory.current/memory.stat  -> cgroup-mem.csv     (proves the cap held; anon vs file)
#   docker stats                       -> docker-stats.jsonl
#   /metrics snapshots every 10 s      -> metrics/<ts>.prom  (pending bg ops, store get durations)
#   mpstat 5 s                         -> mpstat.txt         (server CPU headroom)
set -euo pipefail
source /etc/ebs-blog.env
DATA_DEV="$(basename "$(findmnt -no SOURCE /data)")"   # NVMe names can change across reboots; trust the mount
ACTION="${1:?start|stop}"; PHASE="${2:?phase}"; RUN="${3:?run}"
OUT="/data/results/$PHASE/$RUN"; mkdir -p "$OUT/metrics"
PIDFILE="$OUT/.capture.pids"

if [ "$ACTION" = "start" ]; then
  CID=$(docker ps -q --filter name=weaviate | head -1)
  CG="/sys/fs/cgroup/system.slice/docker-${CID}.scope"
  [ -d "$CG" ] || CG=$(find /sys/fs/cgroup -maxdepth 3 -type d -name "docker-${CID}*" | head -1)
  date -u +%FT%TZ > "$OUT/start.txt"

  # Every background job is fully detached (setsid, no inherited fds), otherwise the SSH session
  # that launched this script never returns.
  setsid nohup iostat -x -o JSON -d 1 "$DATA_DEV" > "$OUT/iostat.json" 2>/dev/null < /dev/null &
  echo $! > "$PIDFILE"

  ( echo "ts,memory_current_bytes,anon_bytes,file_bytes"
    while true; do
      cur=$(cat "$CG/memory.current"); anon=$(awk '$1=="anon"{print $2}' "$CG/memory.stat"); file=$(awk '$1=="file"{print $2}' "$CG/memory.stat")
      echo "$(date +%s),$cur,$anon,$file"; sleep 5
    done ) > "$OUT/cgroup-mem.csv" 2>/dev/null < /dev/null &
  echo $! >> "$PIDFILE"

  ( while true; do docker stats --no-stream --format '{{json .}}' "$CID"; sleep 5; done ) > "$OUT/docker-stats.jsonl" 2>/dev/null < /dev/null &
  echo $! >> "$PIDFILE"

  ( while true; do curl -s localhost:2112/metrics | grep -E '^(vector_index_pending_background_operations|vector_index_store_operations_durations_ms|vector_index_background_operations_durations_ms|object_count|go_memstats_heap_inuse_bytes|process_resident_memory_bytes)' > "$OUT/metrics/$(date +%s).prom" 2>/dev/null; sleep 10; done ) > /dev/null 2>&1 < /dev/null &
  echo $! >> "$PIDFILE"

  setsid nohup mpstat 5 > "$OUT/mpstat.txt" 2>/dev/null < /dev/null &
  echo $! >> "$PIDFILE"
  echo "capture started: $OUT"

elif [ "$ACTION" = "stop" ]; then
  date -u +%FT%TZ > "$OUT/end.txt"
  if [ -f "$PIDFILE" ]; then
    while read -r pid; do pkill -TERM -P "$pid" 2>/dev/null || true; kill -TERM "$pid" 2>/dev/null || true; done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi
  pkill -f "iostat -x -o JSON" 2>/dev/null || true; pkill -f "^mpstat 5" 2>/dev/null || true
  sleep 1
  # iostat's JSON is only closed on a clean exit; repair a truncated file if needed.
  python3 - "$OUT/iostat.json" <<'EOF'
import json, sys
p = sys.argv[1]; s = open(p).read()
try: json.loads(s)
except Exception:
    s = s.rstrip().rstrip(',')
    for tail in ("]}]}}", "}]}]}}", "]}]}]}}"):
        try: json.loads(s + tail); open(p, "w").write(s + tail); break
        except Exception: pass
EOF
  echo "capture stopped: $OUT"
fi
