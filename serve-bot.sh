#!/bin/sh
# Run one bot level in the foreground (for systemd; see install-service.sh).
# Usage: ./serve-bot.sh <level>   (reads tokens/<level>.token)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
LEVEL="${1:?usage: ./serve-bot.sh <level>}"
LICHESS_BOT="${LICHESS_BOT_DIR:-$ROOT/../lichess-bot}"
TOKEN_FILE="$ROOT/tokens/$LEVEL.token"
[ -s "$TOKEN_FILE" ] || { echo "Missing token file: $TOKEN_FILE" >&2; exit 1; }
mkdir -p "$ROOT/.run"
sed "s#__ROOT__#$ROOT#g" "$ROOT/bots/$LEVEL.yml" > "$ROOT/.run/$LEVEL.yml"
cd "$LICHESS_BOT"
LICHESS_BOT_TOKEN="$(cat "$TOKEN_FILE")"
export LICHESS_BOT_TOKEN
exec "$ROOT/.venv/bin/python" lichess-bot.py --config "$ROOT/.run/$LEVEL.yml"
