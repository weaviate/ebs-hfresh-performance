#!/bin/bash
# Thin wrapper: run the benchmarker container against the server. All args pass through.
# Results land in /results/raw/<runID>.json (the tool writes ./results/<runID>.json in its cwd).
set -euo pipefail
source /etc/ebs-blog.env
mkdir -p /results/raw
exec docker run --rm --network host \
  -v /datasets:/datasets:ro -v /results/raw:/app/results \
  benchmarker:local /app/benchmarker ann-benchmark \
  -v "$DATASET" -d cosine -c Sphere --indexType hfresh \
  -u "$SERVER_IP:50051" --httpOrigin "$SERVER_IP:8080" --metricsEndpoint "http://$SERVER_IP:2112/metrics" \
  -f json -l 10 "$@"
