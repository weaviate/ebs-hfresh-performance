#!/bin/bash
# Dead-man's switch. Runs ON the server, independent of the Mac, the tunnel and the credentials.
# At the deadline it stops Weaviate cleanly, uploads whatever results exist, and powers the
# instance off. A stopped instance stops compute billing; the volume must still be destroyed
# from the Mac (provisioned IOPS bill while detached).
# Usage: deadman.sh arm <minutes>   |   deadman.sh disarm   |   deadman.sh status
set -euo pipefail
source /etc/ebs-blog.env
ACTION="${1:?arm|disarm|status}"
UNIT=ebs-blog-deadman

case "$ACTION" in
  arm)
    MIN="${2:?minutes}"
    systemctl stop "$UNIT.timer" 2>/dev/null || true
    systemd-run --unit="$UNIT" --on-active="${MIN}min" --description="ebs-blog dead-man's switch" \
      /bin/bash -c "cd /opt/ebs-blog/compose && docker compose down --timeout 120 >/dev/null 2>&1; \
                    echo \"deadman fired \$(date -u +%FT%TZ)\" >> /data/results/deadman.log; \
                    aws s3 sync /data/results s3://$RESULTS_BUCKET/results/server/ --quiet; \
                    systemctl poweroff" >/dev/null
    echo "deadman armed: poweroff at $(date -u -d "+${MIN} min" +%H:%M) UTC (${MIN} min)"
    ;;
  disarm)
    systemctl stop "$UNIT.timer" 2>/dev/null && echo "deadman disarmed" || echo "deadman was not armed"
    ;;
  status)
    systemctl list-timers "$UNIT.timer" --no-pager 2>/dev/null | sed -n '2p' || echo "not armed"
    ;;
esac
