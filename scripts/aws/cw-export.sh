#!/bin/bash
# Export CloudWatch EBS metrics for the data volume over a window (corroborates iostat).
# Usage: cw-export.sh <phase> <start-iso> <end-iso>    e.g. cw-export.sh phase-1-baseline 2026-09-10T09:00:00Z 2026-09-10T09:40:00Z
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
PHASE="${1:?phase}"; START="${2:?start}"; END="${3:?end}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VOL="$(cd "$HERE/../../infra" && terraform output -raw data_volume_id)"
REGION="$(cd "$HERE/../../infra" && terraform output -raw region)"
OUT="$HERE/../../results/$PHASE"; mkdir -p "$OUT"

q() { jq -n --arg id "$1" --arg m "$2" --arg vol "$VOL" --arg stat "$3" \
  '{Id:$id, MetricStat:{Metric:{Namespace:"AWS/EBS", MetricName:$m, Dimensions:[{Name:"VolumeId",Value:$vol}]}, Period:60, Stat:$stat}}'; }
QUERIES=$(jq -s . <(q readops VolumeReadOps Sum) <(q readbytes VolumeReadBytes Sum) <(q writeops VolumeWriteOps Sum) \
                   <(q queue VolumeQueueLength Average) <(q readtime VolumeTotalReadTime Sum))
aws cloudwatch get-metric-data --region "$REGION" --start-time "$START" --end-time "$END" \
  --metric-data-queries "$QUERIES" --output json > "$OUT/cloudwatch-ebs.json"
echo "wrote $OUT/cloudwatch-ebs.json (IOPS = readops sum / 60 per minute)"
