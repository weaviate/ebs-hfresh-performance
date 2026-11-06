#!/bin/bash
# Change the gp3 limits of the data volume live, then block until the change is complete.
# Run from the Mac with the blog account's AWS profile active.
# Usage: modify-volume.sh <iops> <throughput_mib_s>     e.g. modify-volume.sh 3000 125 | 80000 2000
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
IOPS="${1:?iops}"; TP="${2:?throughput}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VOL="$(cd "$HERE/../../infra" && terraform output -raw data_volume_id)"
REGION="$(cd "$HERE/../../infra" && terraform output -raw region)"
LOG="$HERE/../../results/volume-modifications.log"

echo "$(date -u +%FT%TZ) request iops=$IOPS throughput=$TP vol=$VOL" | tee -a "$LOG"
aws ec2 modify-volume --region "$REGION" --volume-id "$VOL" --iops "$IOPS" --throughput "$TP" \
  --query 'VolumeModification.[ModificationState,OriginalIops,TargetIops,OriginalThroughput,TargetThroughput]' --output text | tee -a "$LOG"
"$HERE/wait-volume.sh"
echo "$(date -u +%FT%TZ) completed iops=$IOPS throughput=$TP" | tee -a "$LOG"
