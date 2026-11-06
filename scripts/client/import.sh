#!/bin/bash
# One-time import of sphere-10M into the Sphere collection with HFresh defaults.
# Run while the server is on compose/import.env (32 GiB cap) and the volume is at 80k/2000.
# Usage: import.sh [ebs-label]      e.g. import.sh 80000-2000
set -euo pipefail
source /etc/ebs-blog.env
EBS="${1:-80000-2000}"
mkdir -p /results/import
start=$(date +%s)
/opt/ebs-blog/scripts/client/bench.sh \
  --maxPostingSizeKB 48 --replicas 4 --rescoreLimit 350 \
  -b 1000 -p 8 --skipQuery \
  --labels "phase=import,ebs=$EBS" \
  -o /app/results/import-stdout.json 2>&1 | tee /results/import/import.log
echo "import wall seconds: $(( $(date +%s) - start ))" | tee -a /results/import/import.log
curl -s "http://$SERVER_IP:8080/v1/schema/Sphere" | python3 -m json.tool > /results/import/schema.json
curl -s "http://$SERVER_IP:8080/v1/nodes?output=verbose" | python3 -m json.tool > /results/import/nodes.json
grep -E '"vectorIndexType"|"searchProbe"|"rescoreLimit"|"bits"|"maxPostingSizeKB"|"replicas"' /results/import/schema.json || true
aws s3 sync /results "s3://$RESULTS_BUCKET/results/client/" --quiet && echo "synced to s3"
