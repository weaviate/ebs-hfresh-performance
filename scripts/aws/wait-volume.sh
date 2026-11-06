#!/bin/bash
# Poll until the most recent modification of the data volume reports "completed".
# Never measure while the state is "modifying" or "optimizing": performance is in between.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VOL="$(cd "$HERE/../../infra" && terraform output -raw data_volume_id)"
REGION="$(cd "$HERE/../../infra" && terraform output -raw region)"
start=$(date +%s)
while true; do
  read -r state prog <<<"$(aws ec2 describe-volumes-modifications --region "$REGION" --volume-ids "$VOL" \
      --query 'VolumesModifications[0].[ModificationState,Progress]' --output text)"
  echo "$(date -u +%T) state=$state progress=$prog% elapsed=$(( $(date +%s) - start ))s"
  [ "$state" = "completed" ] && break
  [ "$state" = "failed" ] && { echo "modification failed"; exit 1; }
  sleep 20
done
aws ec2 describe-volumes --region "$REGION" --volume-ids "$VOL" --query 'Volumes[0].[VolumeType,Size,Iops,Throughput]' --output text
