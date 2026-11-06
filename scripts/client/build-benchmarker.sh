#!/bin/bash
# Build the Weaviate benchmarker as a local docker image (the repo's Dockerfile links HDF5 via CGO,
# which is easier inside the image than on AL2023). Result: image benchmarker:local
set -euo pipefail
cd /opt
if [ ! -d weaviate-benchmarking ]; then git clone --depth 1 https://github.com/weaviate/weaviate-benchmarking; fi
cd weaviate-benchmarking
git rev-parse HEAD > /results/benchmarker-commit.txt
docker build -q -t benchmarker:local ./benchmarker
docker run --rm benchmarker:local /app/benchmarker ann-benchmark -h | head -5
echo "benchmarker:local built ($(cat /results/benchmarker-commit.txt))"
