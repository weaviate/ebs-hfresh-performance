#!/bin/bash
# Run AFTER `terraform destroy`. gp3 provisioned IOPS/throughput bill even when a volume is detached.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REGION="${1:-us-east-2}"
echo "== volumes not attached to anything (must be empty) =="
aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,VolumeType,Iops,Throughput,CreateTime]' --output table
echo "== snapshots owned by this account (delete when the post is published) =="
aws ec2 describe-snapshots --region "$REGION" --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime,Description]' --output table
echo "== running instances (must be empty) =="
aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=running,stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table
