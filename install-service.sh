#!/bin/sh
# Install the per-user systemd template unit maia960-bot@.service for this
# repository. Afterwards, for each level:
#   systemctl --user enable --now maia960-bot@1600
# To keep the bots running after logout and start them at boot, the user needs
# lingering (usually requires an administrator): loginctl enable-linger "$USER"
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/maia960-bot@.service" <<UNIT
[Unit]
Description=Maia-3 Chess960 Lichess bot, level %i
Documentation=https://github.com/MariaRigaki/lichess-bot-maia960

[Service]
Type=simple
ExecStart=$ROOT/serve-bot.sh %i
# Stop lichess-bot together with its multiprocessing children and engines.
KillMode=control-group
KillSignal=SIGINT
TimeoutStopSec=30
# Restart after crashes, but slowly: Lichess asks clients to wait at least a
# minute after HTTP 429, and fast restart loops extend rate limiting.
Restart=on-failure
RestartSec=120
Nice=10

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
echo "Installed $UNIT_DIR/maia960-bot@.service"
echo "Linger: $(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo unknown)"
