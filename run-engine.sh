#!/bin/sh
# UCI engine launcher (used by lichess-bot, or by a GUI such as En Croissant).
# Clears Python and library paths exported by AppImage GUIs.
unset PYTHONHOME PYTHONPATH LD_LIBRARY_PATH LD_PRELOAD
ROOT="$(cd "$(dirname "$0")" && pwd)"
CHECKPOINT="${MAIA3_CHECKPOINT:-$ROOT/checkpoints/maia3-960-ft65536-step150000.pt}"
exec "$ROOT/.venv/bin/python" "$ROOT/engine/maia3_chess960_uci.py" \
  --checkpoint "$CHECKPOINT" --device cpu "$@"
