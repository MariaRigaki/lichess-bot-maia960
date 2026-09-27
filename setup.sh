#!/bin/sh
# Create the project-local environment for the engine and lichess-bot, and
# fetch lichess-bot (unmodified, AGPLv3) next to this repository if missing.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
LICHESS_BOT="${LICHESS_BOT_DIR:-$ROOT/../lichess-bot}"
if [ ! -d "$LICHESS_BOT" ]; then
  git clone --depth 1 https://github.com/lichess-bot-devs/lichess-bot.git "$LICHESS_BOT"
fi
uv venv -q --python 3.12 .venv
uv pip install -q --python .venv --index-url https://download.pytorch.org/whl/cpu torch
uv pip install -q --python .venv numpy huggingface-hub \
  "maia3 @ git+https://github.com/CSSLab/maia3.git@1e13597c42d4858b7cfd7cfdae01e297263364b2" \
  -r "$LICHESS_BOT/requirements.txt"
echo "Environment ready: $ROOT/.venv"
