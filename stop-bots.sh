#!/bin/sh
# Stop bots started by run-bots.sh by signalling each bot's whole process group
# (lichess-bot and its multiprocessing children and engines).
# Usage: ./stop-bots.sh [level ...]   (default: all levels)
#        ./stop-bots.sh --all         also kill any stray process running this
#                                     repository's Python environment
ROOT="$(cd "$(dirname "$0")" && pwd)"
WAIT="${STOP_WAIT_SECONDS:-15}"
PY="$ROOT/.venv/bin/python"

stop_group() {
  PGID="$1"; LABEL="$2"
  pgrep -g "$PGID" >/dev/null || return 0
  echo "Stopping $LABEL (process group $PGID)"
  pkill -INT -g "$PGID"
  i=0
  while [ $i -lt "$WAIT" ] && pgrep -g "$PGID" >/dev/null; do sleep 1; i=$((i + 1)); done
  if pgrep -g "$PGID" >/dev/null; then
    echo "  still running after ${WAIT}s; terminating"
    pkill -TERM -g "$PGID"; sleep 2
    pgrep -g "$PGID" >/dev/null && pkill -KILL -g "$PGID"
  fi
  return 0
}

ALL=0; LEVELS=""
for ARG in "$@"; do
  if [ "$ARG" = "--all" ]; then ALL=1; else LEVELS="$LEVELS $ARG"; fi
done
[ -n "$LEVELS" ] || LEVELS="1300 1600 1900"

for LEVEL in $LEVELS; do
  PGID_FILE="$ROOT/.run/$LEVEL.pgid"
  if [ -s "$PGID_FILE" ]; then
    stop_group "$(cat "$PGID_FILE")" "level $LEVEL"
    rm -f "$PGID_FILE"
  fi
done

if [ "$ALL" = 1 ]; then
  STRAY="$(ps -eo pid=,args= | awk -v py="$PY" '$2 == py {print $1}')"
  if [ -n "$STRAY" ]; then
    echo "Killing stray processes: $(echo $STRAY)"
    echo "$STRAY" | xargs kill -TERM 2>/dev/null; sleep 2
    STRAY="$(ps -eo pid=,args= | awk -v py="$PY" '$2 == py {print $1}')"
    [ -n "$STRAY" ] && echo "$STRAY" | xargs kill -KILL 2>/dev/null
  fi
fi
REMAINING="$(ps -eo pid=,args= | awk -v py="$PY" '$2 == py {print $1}')"
[ -n "$REMAINING" ] && echo "Note: processes still use this environment: $(echo $REMAINING) (see ./stop-bots.sh --all)"
exit 0
