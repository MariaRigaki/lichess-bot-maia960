#!/bin/sh
# Start one lichess-bot process per level, each in its own process group so
# that stop-bots.sh can stop lichess-bot together with its child processes.
# Tokens are read from tokens/<level>.token (one line, chmod 600, not in git).
# Usage: ./run-bots.sh [level ...]   (default: 1300 1600 1900)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
LICHESS_BOT="${LICHESS_BOT_DIR:-$ROOT/../lichess-bot}"
LEVELS="${*:-1300 1600 1900}"
mkdir -p "$ROOT/.run" "$ROOT/logs"
for LEVEL in $LEVELS; do
  TOKEN_FILE="$ROOT/tokens/$LEVEL.token"
  PGID_FILE="$ROOT/.run/$LEVEL.pgid"
  if [ ! -s "$TOKEN_FILE" ]; then
    echo "Missing token file: $TOKEN_FILE" >&2
    exit 1
  fi
  if [ -s "$PGID_FILE" ] && pgrep -g "$(cat "$PGID_FILE")" >/dev/null; then
    echo "Level $LEVEL is already running (process group $(cat "$PGID_FILE")); run ./stop-bots.sh $LEVEL first." >&2
    continue
  fi
  sed "s#__ROOT__#$ROOT#g" "$ROOT/bots/$LEVEL.yml" > "$ROOT/.run/$LEVEL.yml"
  (
    cd "$LICHESS_BOT"
    LICHESS_BOT_TOKEN="$(cat "$TOKEN_FILE")" setsid nice -n 10 \
      "$ROOT/.venv/bin/python" lichess-bot.py --config "$ROOT/.run/$LEVEL.yml" \
      > "$ROOT/logs/$LEVEL.log" 2>&1 < /dev/null &
    echo $! > "$PGID_FILE"
  )
  echo "Started level $LEVEL (process group $(cat "$PGID_FILE"), log logs/$LEVEL.log)"
done
