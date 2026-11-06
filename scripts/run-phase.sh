#!/bin/bash
# Mac-side orchestrator for one measurement phase. Everything goes through SSM, nothing through SSH.
# Usage: run-phase.sh <phase> <env-file> <ebs-label> [quick]
#   run-phase.sh phase-2-max      headline.env 80000-2000
#   run-phase.sh phase-1-baseline headline.env 3000-125
#   run-phase.sh phase-3-control  control.env  80000-2000
# Pre-condition: the volume already reports the limits named in <ebs-label> (scripts/aws/modify-volume.sh).
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-ebs-blog}"
PHASE="${1:?phase}"; ENVFILE="${2:?env file}"; EBS="${3:?ebs label}"; QUICK="${4:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"; SSM="$HERE/aws/ssm.sh"; PRE="$HERE/aws/preflight.sh"
DEADMAN_MIN="${DEADMAN_MIN:-90}"   # server powers itself off this many minutes after the phase starts
"$PRE"
echo "== [$PHASE] arm dead-man's switch ($DEADMAN_MIN min)"
"$SSM" server "/opt/ebs-blog/scripts/server/deadman.sh arm $DEADMAN_MIN"
BUCKET="$(cd "$HERE/../infra" && terraform output -raw results_bucket)"

if [ "${SKIP_RESET:-0}" = "1" ]; then
  echo "== [$PHASE] SKIP_RESET=1: server already reset"
else
  echo "== [$PHASE] reset server ($ENVFILE)"
  "$SSM" server "/opt/ebs-blog/scripts/server/reset.sh $PHASE $ENVFILE"
fi
"$PRE"; echo "== [$PHASE] start host capture"
"$SSM" server "/opt/ebs-blog/scripts/server/capture.sh start $PHASE sweep"
START=$(date -u +%FT%TZ)
"$PRE"; echo "== [$PHASE] sweep from client (detached; the tunnel is not held open)"
"$SSM" client "rm -f /results/$PHASE/DONE /results/$PHASE/FAILED; nohup /opt/ebs-blog/scripts/client/sweep.sh $PHASE $EBS $QUICK > /results/$PHASE.nohup.log 2>&1 < /dev/null & disown; echo launched"
# Poll with short sessions. Each check is its own SSH; an expired token or dropped tunnel only costs one poll.
for i in $(seq 1 90); do
  sleep 60
  st=$("$SSM" client "if [ -f /results/$PHASE/DONE ]; then echo DONE; elif [ -f /results/$PHASE/FAILED ]; then echo FAILED; else grep -oE 'Benchmark result.*qps=[0-9.]+' /results/$PHASE/sweep.log 2>/dev/null | tail -1 | sed -E 's/.*parallel=([0-9]+) qps=([0-9.]+).*/last: p=\1 qps=\2/' || echo running; fi" 2>/dev/null | tail -1 || echo "poll failed")
  echo "$(date -u +%H:%M) [$PHASE] $st"
  case "$st" in DONE|FAILED) break;; esac
done
[ "$st" = "DONE" ] || { echo "== [$PHASE] sweep did not finish cleanly ($st); capture is stopped and results pulled anyway"; }
END=$(date -u +%FT%TZ)
"$PRE" || true; echo "== [$PHASE] stop capture, sync server results"
"$SSM" server "/opt/ebs-blog/scripts/server/capture.sh stop $PHASE sweep; aws s3 sync /data/results s3://$BUCKET/results/server/ --quiet && echo synced"
echo "== [$PHASE] cloudwatch export $START .. $END"
sleep 120   # CloudWatch EBS metrics lag by a minute or two
"$HERE/aws/cw-export.sh" "$PHASE" "$START" "$END" || echo "cloudwatch export failed (non-fatal)"
"$HERE/aws/pull-results.sh"
"$SSM" server "/opt/ebs-blog/scripts/server/deadman.sh disarm" || true
echo "== [$PHASE] done $(date -u +%H:%M) UTC. Render with: python3 scripts/analyze/render.py"
