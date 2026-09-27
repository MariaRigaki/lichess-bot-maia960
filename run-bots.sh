#!/bin/sh
# Start one lichess-bot process per level. Tokens are read from
# tokens/<level>.token (one line, chmod 600, not in git).
# Usage: ./run-bots.sh [level ...]   (default: 1300 1600 1900)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
LICHESS_BOT="${LICHESS_BOT_DIR:-$ROOT/../lichess-bot}"
LEVELS="${*:-1300 1600 1900}"
mkdir -p "$ROOT/.run" "$ROOT/logs"
for LEVEL in $LEVELS; do
  TOKEN_FILE="$ROOT/tokens/$LEVEL.token"
  if [ ! -s "$TOKEN_FILE" ]; then
    echo "Missing token file: $TOKEN_FILE" >&2
    exit 1
  fi
  if pgrep -f "lichess-bot.py --config $ROOT/.run/$LEVEL.yml" >/dev/null; then
    echo "Level $LEVEL is already running; run ./stop-bots.sh $LEVEL first." >&2
    continue
  fi
  sed "s#__ROOT__#$ROOT#g" "$ROOT/bots/$LEVEL.yml" > "$ROOT/.run/$LEVEL.yml"
  (
    cd "$LICHESS_BOT"
    LICHESS_BOT_TOKEN="$(cat "$TOKEN_FILE")" nohup nice -n 10 \
      "$ROOT/.venv/bin/python" lichess-bot.py --config "$ROOT/.run/$LEVEL.yml" \
      > "$ROOT/logs/$LEVEL.log" 2>&1 &
    echo $! > "$ROOT/.run/$LEVEL.pid"
  )
  echo "Started level $LEVEL (pid $(cat "$ROOT/.run/$LEVEL.pid"), log logs/$LEVEL.log)"
done
