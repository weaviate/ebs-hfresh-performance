#!/bin/bash
# Mac-side orchestrator for day 0: tooling, dataset check, import, idle wait, snapshot.
# Pre-conditions: terraform applied, sync-to-hosts.sh run, volume at 80000/2000.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"; SSM="$HERE/aws/ssm.sh"
REGION="$(cd "$HERE/../infra" && terraform output -raw region)"
VOL="$(cd "$HERE/../infra" && terraform output -raw data_volume_id)"
BUCKET="$(cd "$HERE/../infra" && terraform output -raw results_bucket)"

echo "== server: image shell check, calibration, start weaviate with import.env"
"$SSM" server "docker run --rm --entrypoint /bin/sh cr.weaviate.io/semitechnologies/weaviate:1.39.3 -c 'echo image-has-shell'"
"$SSM" server "/opt/ebs-blog/scripts/server/reset.sh phase-0-calibration import.env"
echo "== client: build benchmarker, check dataset"
"$SSM" client "/opt/ebs-blog/scripts/client/build-benchmarker.sh"
"$SSM" client "/opt/ebs-blog/scripts/client/check-dataset.sh"
echo "== client: import (long; SSM command timeout is 1 h, so it runs detached and we poll the log)"
"$SSM" client "nohup /opt/ebs-blog/scripts/client/import.sh ${EBS_LABEL:-80000-2000} > /results/import-nohup.log 2>&1 < /dev/null & disown"
while ! "$SSM" client "grep -q 'import wall seconds' /results/import/import.log && tail -3 /results/import/import.log" 2>/dev/null; do
  "$SSM" client "tail -1 /results/import/import.log 2>/dev/null || echo waiting" | tail -1
  sleep 300
done
echo "== server: wait for background work and compactions to finish"
"$SSM" server "/opt/ebs-blog/scripts/server/wait-idle.sh 10 5 | tail -3; du -sh /data/weaviate | tee /data/results/phase-0-calibration/disk-footprint-after-import.txt"
echo "== server: stop weaviate"
"$SSM" server "cd /opt/ebs-blog/compose && docker compose --env-file import.env down --timeout 120 && sync"
if [ "$VOL" != "none" ]; then
  echo "== snapshot the volume as a rollback point"
  aws ec2 create-snapshot --region "$REGION" --volume-id "$VOL" --description "sphere-10M hfresh imported" \
    --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Project,Value=ebs-hfresh-blog}]' --query SnapshotId --output text | tee results/snapshot-id.txt
else
  echo "== instance-store data: no snapshot possible (data is lost if the instance stops; the dead-man's switch stops, not terminates, but NVMe still clears)"
fi
"$SSM" server "aws s3 sync /data/results s3://$BUCKET/results/server/ --quiet && echo synced"
"$HERE/aws/pull-results.sh"
echo "== import done. Next: scripts/run-phase.sh phase-2-max headline.env 80000-2000"
