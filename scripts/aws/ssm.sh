#!/bin/bash
# Remote exec on the server or the client, tunnelled through the EC2 Instance Connect Endpoint
# (SSH over the AWS API, no public ingress, no stored key pair: a throw-away key is pushed for 60 s).
# Kept under the name ssm.sh because every orchestrator calls it; SSM Run Command was rejected with
# AccessDenied on this account, so EICE is the path.
# Usage: ssm.sh server|client [command]
#   Without a command: interactive root shell. With a command: run it as root, print the output.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
TARGET="${1:?server|client}"; shift || true
HERE="$(cd "$(dirname "$0")" && pwd)"
ID="$(cd "$HERE/../../infra" && terraform output -raw "${TARGET}_instance_id")"
export AWS_REGION="$(cd "$HERE/../../infra" && terraform output -raw region)"
KEY="$HOME/.ssh/ebs-blog-eic"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -f "$KEY" -C ebs-blog-eic

aws ec2-instance-connect send-ssh-public-key --instance-id "$ID" --instance-os-user ec2-user \
  --ssh-public-key "file://$KEY.pub" --query Success --output text >/dev/null
SSH=(ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -o ServerAliveInterval=30
     -o ProxyCommand="aws ec2-instance-connect open-tunnel --instance-id %h" -i "$KEY" "ec2-user@$ID")

if [ $# -eq 0 ]; then
  exec "${SSH[@]}" -t sudo -i
fi
# Command text goes over stdin, so quoting on the caller side is never an issue.
"${SSH[@]}" 'sudo bash -s' <<<"$*"
