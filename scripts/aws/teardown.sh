#!/bin/bash
# Full teardown: pull results, stop Weaviate, destroy everything Terraform made, delete the snapshot,
# then prove nothing billable is left. Safe to re-run.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
"$HERE/preflight.sh"
REGION="$(cd "$ROOT/infra" && terraform output -raw region 2>/dev/null || echo us-east-2)"

echo "== pull whatever results exist"
"$HERE/pull-results.sh" >/dev/null 2>&1 || echo "(pull skipped: hosts or bucket unreachable)"
echo "== stop weaviate (best effort)"
"$HERE/ssm.sh" server 'cd /opt/ebs-blog/compose && docker compose down --timeout 60 >/dev/null 2>&1; /opt/ebs-blog/scripts/server/deadman.sh disarm; aws s3 sync /data/results s3://'"$(cd "$ROOT/infra" && terraform output -raw results_bucket)"'/results/server/ --quiet; echo stopped' 2>/dev/null || echo "(server unreachable, continuing)"
"$HERE/pull-results.sh" >/dev/null 2>&1 || true

echo "== terraform destroy"
(cd "$ROOT/infra" && terraform destroy -input=false -auto-approve -no-color 2>&1 | grep -E 'Destruction complete|Destroy complete|Error' | sed -E 's/\[id=[^]]*\]//')

echo "== delete snapshot"
if [ -f "$ROOT/results/snapshot-id.txt" ]; then
  SNAP=$(cat "$ROOT/results/snapshot-id.txt")
  aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$SNAP" 2>/dev/null && echo "deleted $SNAP" || echo "snapshot $SNAP already gone"
fi

echo "== what is left (all must be empty)"
aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,InstanceType,State.Name]' --output text
aws ec2 describe-volumes --region "$REGION" --query 'Volumes[].[VolumeId,Size,Iops,Throughput,State]' --output text
aws ec2 describe-snapshots --region "$REGION" --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,State]' --output text
aws ec2 describe-instance-connect-endpoints --region "$REGION" --query 'InstanceConnectEndpoints[].[InstanceConnectEndpointId,State]' --output text
aws s3 ls 2>/dev/null | grep ebs-hfresh || true
echo "== teardown finished $(date -u +%H:%M) UTC"
