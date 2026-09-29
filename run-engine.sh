#!/bin/sh
# UCI engine launcher (used by lichess-bot, or by a GUI such as En Croissant).
# Clears Python and library paths exported by AppImage GUIs.
# Optional local settings (not in git) go in engine.env, for example:
#   MAIA3_CHECKPOINT=/path/to/ft79m-65536-step116000.pt
#   MAIA3_THREADS=1
unset PYTHONHOME PYTHONPATH LD_LIBRARY_PATH LD_PRELOAD
ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$ROOT/engine.env" ] && . "$ROOT/engine.env"
CHECKPOINT="${MAIA3_CHECKPOINT:-$ROOT/checkpoints/maia3-960-ft65536-step150000.pt}"
exec "$ROOT/.venv/bin/python" "$ROOT/engine/maia3_chess960_uci.py" \
  --checkpoint "$CHECKPOINT" --model "${MAIA3_MODEL:-auto}" \
  --threads "${MAIA3_THREADS:-2}" --device cpu "$@"
