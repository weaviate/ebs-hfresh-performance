#!/bin/bash
# Fail fast if the credentials are dead or old. Every orchestrator sources this before each remote step.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
if ! aws sts get-caller-identity --query Arn --output text >/dev/null 2>&1; then
  echo "PREFLIGHT FAILED $(date -u +%H:%M): ebs-blog credentials rejected (expired?). Reload with scripts/aws/load-keys.sh" >&2
  exit 97
fi
if [ -f "$HOME/.aws/ebs-blog.loaded-at" ]; then
  age=$(( ( $(date -u +%s) - $(cat "$HOME/.aws/ebs-blog.loaded-at") ) / 60 ))
  [ "$age" -gt 240 ] && echo "PREFLIGHT WARNING: credentials loaded ${age} min ago; typical session lifetime is a few hours" >&2
fi
exit 0
