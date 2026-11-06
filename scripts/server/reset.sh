#!/bin/bash
# Put the server into an identical cold state before a measurement phase.
# Usage: reset.sh <phase> <env-file>      e.g. reset.sh phase-1-baseline headline.env
#   1. fio calibration (proves the volume's current limits)
#   2. stop weaviate, drop page cache, pin readahead
#   3. start weaviate with the given RAM cap, wait for ready
set -euo pipefail
source /etc/ebs-blog.env
PHASE="${1:?phase}"; ENVFILE="${2:?env file, e.g. headline.env}"
COMPOSE_DIR=/opt/ebs-blog/compose
OUT="/data/results/$PHASE"; mkdir -p "$OUT"
cd "$COMPOSE_DIR"

docker compose --env-file "$ENVFILE" down --timeout 120 || true
/opt/ebs-blog/scripts/server/fio-calibrate.sh "$PHASE"
sync; echo 3 > /proc/sys/vm/drop_caches
/opt/ebs-blog/scripts/server/tune-disk.sh "$PHASE"
cp "$ENVFILE" "$OUT/compose-env.txt"

docker compose --env-file "$ENVFILE" up -d
for i in $(seq 1 120); do
  if curl -sf localhost:8080/v1/.well-known/ready >/dev/null; then break; fi
  sleep 5
done
curl -sf localhost:8080/v1/.well-known/ready >/dev/null || { echo "weaviate not ready"; docker compose logs --tail 50; exit 1; }

CID=$(docker compose ps -q weaviate)
echo "CID=$CID" > "$OUT/container.env"
docker inspect "$CID" --format '{{.HostConfig.Memory}} {{.HostConfig.MemorySwap}} {{.HostConfig.NanoCpus}}' \
  | awk '{printf "container mem_limit=%.1fGiB memswap=%.1fGiB cpus=%.0f\n", $1/2^30, $2/2^30, $3/1e9}' | tee "$OUT/container-limits.txt"
curl -s localhost:8080/v1/meta | jq -c '{version, hostname}' | tee "$OUT/meta.json"
du -sh /data/weaviate | tee "$OUT/disk-footprint.txt"
echo "reset done for $PHASE; run a 60 s warm-up from the client before measuring"
