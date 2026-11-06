#!/bin/bash
# The measurement sweep. Identical for every phase; only the labels differ.
#   warm-up (discarded), then parallel {8,32,128} x searchProbe {32,64,128,256} x 120 s,
#   then rescoreLimit {100,350,1000} at searchProbe 64 / parallel 32.
# Usage: sweep.sh <phase> <ebs-label> [quick]     e.g. sweep.sh phase-1-baseline 3000-125
#   "quick" shortens every run to 30 s for a dry run.
set -euo pipefail
source /etc/ebs-blog.env
PHASE="${1:?phase}"; EBS="${2:?ebs label like 3000-125}"; MODE="${3:-full}"
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAILED rc=$rc at line $LINENO" > "/results/$PHASE/FAILED"; aws s3 sync /results "s3://$RESULTS_BUCKET/results/client/" --quiet 2>/dev/null || true; fi' EXIT
DUR=120; PARALLELS="8 32 128"; PROBES="32,64,128,256"; RESCORES="100 350 1000"
case "$MODE" in
  quick)   DUR=30;;
  compact) DUR=60; PARALLELS="32 128"; PROBES="64,256"; RESCORES="100 1000";;   # time-boxed: ~12 min at 10 QPS
esac
OUT="/results/$PHASE"; mkdir -p "$OUT"; rm -f "$OUT/DONE" "$OUT/FAILED"
BENCH=/opt/ebs-blog/scripts/client/bench.sh
Q="-q --existingSchema --queryDelaySeconds 0 --skipMemoryStats"

run() { # run <name> <args...>  -> copies the newest raw JSON to $OUT/<name>.json
  local name="$1"; shift
  echo "$(date -u +%T) run $name: $*" | tee -a "$OUT/sweep.log"
  before=$(ls -t /results/raw/*.json 2>/dev/null | head -1 || true)
  $BENCH $Q "$@" 2>&1 | tee -a "$OUT/sweep.log" | grep -E 'Benchmark result|error|Error' || true
  after=$(ls -t /results/raw/*.json 2>/dev/null | head -1 || true)
  if [ -n "$after" ] && [ "$after" != "$before" ]; then cp "$after" "$OUT/$name.json"; else echo "WARNING: no new result file for $name" | tee -a "$OUT/sweep.log"; fi
  aws s3 sync /results "s3://$RESULTS_BUCKET/results/client/" --quiet 2>/dev/null || true   # nothing is lost if the Mac side dies
}

echo "sweep $PHASE ebs=$EBS started $(date -u +%FT%TZ)" | tee "$OUT/sweep.log"
# Warm-up: discarded, same settings as the headline point.
run warmup --rescoreLimit 350 --efArray 64 -p 32 --queryDuration 60 --labels "phase=$PHASE,ebs=$EBS,kind=warmup"
rm -f "$OUT/warmup.json"

for p in $PARALLELS; do
  run "probe-sweep-p$p" --rescoreLimit 350 --efArray "$PROBES" -p "$p" --queryDuration "$DUR" \
      --labels "phase=$PHASE,ebs=$EBS,kind=probe,parallel=$p"
done
# The benchmarker's --rescoreLimit only applies at collection creation; in query-only mode the
# value must be changed through the schema API (rq.rescoreLimit is mutable at runtime).
set_rescore() {
  curl -s "http://$SERVER_IP:8080/v1/schema/Sphere" \
    | python3 -c "import json,sys; c=json.load(sys.stdin); c['vectorIndexConfig']['rq']['rescoreLimit']=int(sys.argv[1]); print(json.dumps(c))" "$1" \
    | curl -s -X PUT -H 'Content-Type: application/json' -d @- "http://$SERVER_IP:8080/v1/schema/Sphere" >/dev/null
  echo "rescoreLimit now $(curl -s "http://$SERVER_IP:8080/v1/schema/Sphere" | python3 -c "import json,sys; print(json.load(sys.stdin)['vectorIndexConfig']['rq']['rescoreLimit'])")" | tee -a "$OUT/sweep.log"
}
for r in $RESCORES; do
  set_rescore "$r"
  run "rescore-r$r-p32" --efArray 64 -p 32 --queryDuration "$DUR" \
      --labels "phase=$PHASE,ebs=$EBS,kind=rescore,parallel=32,rescore=$r"
done
# Put rescoreLimit back to the default so the schema is identical for the next phase.
set_rescore 350
curl -s "http://$SERVER_IP:8080/v1/schema/Sphere" | python3 -m json.tool > "$OUT/schema-after.json"
echo "sweep $PHASE finished $(date -u +%FT%TZ)" | tee -a "$OUT/sweep.log"
date -u +%FT%TZ > "$OUT/DONE"
aws s3 sync /results "s3://$RESULTS_BUCKET/results/client/" --quiet && echo "synced to s3"
