#!/bin/bash
# Server bootstrap: docker + compose, sysstat/fio, mount the gp3 data volume at /data.
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

dnf install -y docker sysstat fio jq htop git bc

# docker compose v2 plugin
COMPOSE_VERSION="v2.29.7"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
systemctl enable --now docker
usermod -aG docker ec2-user || true
usermod -aG docker ssm-user || true

if [ "${data_disk}" = "nvme" ]; then
  # Instance-store NVMe: pick the first (largest) "Amazon EC2 NVMe Instance Storage" device.
  DEV=""
  for i in $(seq 1 30); do
    best=0
    for d in /sys/block/nvme*n1; do
      [ -e "$d/device/model" ] || continue
      if grep -qi "Instance Storage" "$d/device/model"; then
        sz=$(cat "$d/size"); if [ "$sz" -gt "$best" ]; then best=$sz; DEV="/dev/$(basename "$d")"; fi
      fi
    done
    [ -n "$DEV" ] && break; sleep 2
  done
  [ -n "$DEV" ] || { echo "no instance-store NVMe found"; lsblk -o NAME,MODEL,SIZE; exit 1; }
  echo "instance-store device: $DEV"
else
  # Wait for the data volume. On Nitro the EBS volume id is visible in the by-id symlink.
  VOL_ID_NODASH="$(echo "${volume_id}" | tr -d '-')"
  DEV_LINK="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$${VOL_ID_NODASH}"
  for i in $(seq 1 60); do
    [ -e "$DEV_LINK" ] && break
    sleep 5
  done
  [ -e "$DEV_LINK" ] || { echo "data volume not attached"; exit 1; }
  DEV="$(readlink -f "$DEV_LINK")"
fi

if ! blkid "$DEV" >/dev/null 2>&1; then
  mkfs.ext4 -m0 -E lazy_itable_init=0,lazy_journal_init=0 -L weaviate-data "$DEV"
fi
mkdir -p /data
# Instance-store data does not survive a stop, so mount it nofail: a reboot must not hang on it.
grep -q 'LABEL=weaviate-data' /etc/fstab || echo 'LABEL=weaviate-data /data ext4 defaults,noatime,nodiratime,nofail 0 2' >> /etc/fstab
mount -a
mkdir -p /data/weaviate /data/results
chmod 777 /data/weaviate /data/results

# Persist the device name and settings for the scripts.
cat > /etc/ebs-blog.env <<EOF
DATA_DEV=$(basename "$DEV")
DATA_DISK=${data_disk}
VOLUME_ID=${volume_id}
RESULTS_BUCKET=${results_bucket}
WEAVIATE_VERSION=${weaviate_version}
EOF

# Pre-pull the image so phase resets are fast.
docker pull "cr.weaviate.io/semitechnologies/weaviate:${weaviate_version}" || true

# Disable swap entirely (the RAM cap must be a hard cap).
swapoff -a || true
echo "server bootstrap done"
