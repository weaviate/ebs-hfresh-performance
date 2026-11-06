#!/bin/bash
# Pull everything both hosts uploaded into results/ on the Mac.
#   results/<phase>/              client JSON (benchmarker) + sweep.log + schema-after.json
#   results/<phase>/sweep/        server capture (iostat.json, cgroup-mem.csv, metrics/, mpstat.txt)
#   results/<phase>/fio-*.json, host-state.txt, container-limits.txt, disk-footprint.txt
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
BUCKET="$(cd "$ROOT/infra" && terraform output -raw results_bucket)"
aws s3 sync "s3://$BUCKET/results/client/" "$ROOT/results/" --exclude 'raw/*' --quiet
aws s3 sync "s3://$BUCKET/results/server/" "$ROOT/results/" --quiet
find "$ROOT/results" -maxdepth 2 -type d | sort
