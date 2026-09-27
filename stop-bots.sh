#!/bin/sh
# Stop the bots started by run-bots.sh, found by their config path (not only by
# pid file, so leftover processes are stopped too).
# Usage: ./stop-bots.sh [level ...]   (default: all levels)
# lichess-bot is interrupted first so it can finish; processes still running
# after the wait are terminated.
ROOT="$(cd "$(dirname "$0")" && pwd)"
LEVELS="${*:-1300 1600 1900}"
WAIT="${STOP_WAIT_SECONDS:-15}"
for LEVEL in $LEVELS; do
  PATTERN="lichess-bot.py --config $ROOT/.run/$LEVEL.yml"
  PIDS="$(pgrep -f "$PATTERN")"
  [ -n "$PIDS" ] || continue
  echo "Stopping level $LEVEL (pids: $(echo $PIDS))"
  kill -INT $PIDS 2>/dev/null
  i=0
  while [ $i -lt "$WAIT" ] && pgrep -f "$PATTERN" >/dev/null; do
    sleep 1; i=$((i + 1))
  done
  if pgrep -f "$PATTERN" >/dev/null; then
    echo "Level $LEVEL still running after ${WAIT}s; terminating."
    pkill -TERM -f "$PATTERN"
  fi
  rm -f "$ROOT/.run/$LEVEL.pid"
done
