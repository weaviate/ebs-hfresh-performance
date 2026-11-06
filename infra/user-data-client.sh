#!/bin/bash
# Client bootstrap: docker (the benchmarker builds inside its own image), h5py for dataset checks,
# dataset download in the background.
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

dnf install -y docker git jq htop python3-pip
pip3 install --quiet h5py numpy      # wheels bundle libhdf5; no hdf5-devel package exists on AL2023
systemctl enable --now docker
usermod -aG docker ec2-user || true

cat > /etc/ebs-blog.env <<EOF
SERVER_IP=${server_private_ip}
RESULTS_BUCKET=${results_bucket}
DATASET=/datasets/sphere-10M-meta-dpr.hdf5
EOF

mkdir -p /datasets /results
chmod 777 /datasets /results

# Dataset download in the background (31 GB). Wall time is logged for the post.
nohup bash -c 'start=$(date +%s); curl -fsSL -o /datasets/sphere-10M-meta-dpr.hdf5.part "${dataset_url}" && mv /datasets/sphere-10M-meta-dpr.hdf5.part /datasets/sphere-10M-meta-dpr.hdf5; echo "download seconds: $(( $(date +%s) - start ))" > /datasets/download.log' \
  > /datasets/download.out 2>&1 &

echo "client bootstrap done"
