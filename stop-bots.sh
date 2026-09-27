#!/bin/sh
# Stop the bots started by run-bots.sh. lichess-bot finishes running games first
# (quit_after_all_games_finish: true); run twice to force an immediate stop.
ROOT="$(cd "$(dirname "$0")" && pwd)"
for PID_FILE in "$ROOT"/.run/*.pid; do
  [ -e "$PID_FILE" ] || continue
  kill -INT "$(cat "$PID_FILE")" 2>/dev/null && echo "Stopping $(basename "$PID_FILE" .pid)"
done
