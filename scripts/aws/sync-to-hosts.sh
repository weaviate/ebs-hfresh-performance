#!/bin/bash
# Ship compose files and scripts to both instances via the results bucket (no SSH path exists).
# Usage: sync-to-hosts.sh
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
BUCKET="$(cd "$ROOT/infra" && terraform output -raw results_bucket)"
aws s3 sync "$ROOT/compose" "s3://$BUCKET/bundle/compose" --delete
aws s3 sync "$ROOT/scripts" "s3://$BUCKET/bundle/scripts" --delete
for t in server client; do
  "$HERE/ssm.sh" "$t" "mkdir -p /opt/ebs-blog && aws s3 sync s3://$BUCKET/bundle /opt/ebs-blog --delete && chmod +x /opt/ebs-blog/scripts/*/*.sh && echo synced-$t"
done
