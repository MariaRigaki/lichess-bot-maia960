#!/bin/sh
# Upgrade a fresh Lichess account to a BOT account (IRREVERSIBLE).
# The account must never have played a game; the token needs the bot:play scope.
# Usage: ./upgrade-bot.sh <level>   (reads tokens/<level>.token)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
LEVEL="${1:?usage: ./upgrade-bot.sh <level>}"
TOKEN_FILE="$ROOT/tokens/$LEVEL.token"
[ -s "$TOKEN_FILE" ] || { echo "Missing token file: $TOKEN_FILE" >&2; exit 1; }
AUTH="Authorization: Bearer $(cat "$TOKEN_FILE")"
ACCOUNT="$(curl -s https://lichess.org/api/account -H "$AUTH")"
USERNAME="$(printf '%s' "$ACCOUNT" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
[ -n "$USERNAME" ] || { echo "Token not accepted by Lichess: $ACCOUNT" >&2; exit 1; }
if printf '%s' "$ACCOUNT" | grep -q '"title":"BOT"'; then
  echo "$USERNAME is already a BOT account."; exit 0
fi
printf 'Upgrade %s to a BOT account? This cannot be undone. Type the username to confirm: ' "$USERNAME"
read -r ANSWER
[ "$ANSWER" = "$USERNAME" ] || { echo "Not confirmed; nothing changed."; exit 1; }
curl -s -X POST https://lichess.org/api/bot/account/upgrade -H "$AUTH"; echo
