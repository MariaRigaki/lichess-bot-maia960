# Maia-3 Chess960 bots

Hobby deployment of Maia-3 models fine-tuned on Lichess Chess960 blitz
games (65,536 training games) in the chess_960 research project. The default
is the 5M model (update 150,000); the fine-tuned 79M model (update 116,000)
predicts Chess960 moves better and can be selected in `engine.env`. Three Lichess BOT accounts imitate players rated about 1300, 1600,
and 1900. The bots only predict human moves; they do not search, and their
nominal level is a model input, not a measured playing strength.

## Components

- `engine/maia3_chess960_uci.py`: UCI engine. Supports Chess960 (detected from
  the position or set with `UCI_Chess960`), and accepts both castling
  notations. Options:
  - `SelfElo`: the rating the bot imitates.
  - `OppoElo`: the opponent's rating, set automatically per game via the
    standard `UCI_Opponent` option.
  - `Temperature`: 1.0 samples human-like moves; lower values play stronger
    than the nominal rating; 0 always plays the most likely move.
  - `TopP`: nucleus sampling. Only the smallest set of most likely moves whose
    total probability reaches TopP can be played (1.0 disables it). This removes
    rare, unlikely moves while keeping variety among plausible ones.
- `engine/maia3_adapter.py`: board history, legal-move mapping, and Chess960
  castling-action adapter (from the research code).
- `run-engine.sh`: engine launcher, also usable from a GUI such as En Croissant.
- `bots/{1300,1600,1900}.yml`: lichess-bot configurations (casual or rated games, as the challenger chooses;
  Chess960 only, bullet to rapid (base 1–25 minutes, increment up to
  20 seconds), humans only, two simultaneous games per bot and one per opponent,
  no books or tablebases, no automatic draw offers or resignations). The bots use Temperature 0.8 and TopP 0.9, tuned from test games: at Temperature 1.0 without TopP the bot played too many unlikely moves, and TopP 0.95 still felt too easy. The model
  was trained on blitz moves made with at least 30 seconds on the clock, so
  bullet play imitates unhurried blitz rather than bullet habits.
- `run-bots.sh` / `stop-bots.sh`: start and stop one lichess-bot process per
  level (manual use). `serve-bot.sh` and `install-service.sh`: systemd hosting. `upgrade-bot.sh`: upgrade a fresh account to BOT.
- `tests/smoke_engine.py`: drives the engine through python-chess as
  lichess-bot does.

## Setup

1. Clone this repository and run `./setup.sh`:
   `git clone https://github.com/MariaRigaki/lichess-bot-maia960.git && cd lichess-bot-maia960 && ./setup.sh`.
   The script requires [uv](https://docs.astral.sh/uv/). It creates `.venv/`
   (CPU PyTorch, pinned `maia3`, lichess-bot requirements) and clones
   [lichess-bot](https://github.com/lichess-bot-devs/lichess-bot) next to this
   repository if missing. Override its location with `LICHESS_BOT_DIR`.
2. Put the checkpoint at `checkpoints/maia3-960-ft65536-step150000.pt`
   (SHA-256 `14e89c7e0557a020d5424a9746dd1e1a5c8aee6f27d3220250482bad82dfcafa`),
   or set `MAIA3_CHECKPOINT`. It is not in git.
   To use another checkpoint, such as the fine-tuned 79M model, create
   `engine.env` (not in git) next to `run-engine.sh`:
   ```sh
   MAIA3_CHECKPOINT=/path/to/ft79m-65536-step116000.pt
   MAIA3_THREADS=1
   ```
   (SHA-256 of the 79M checkpoint:
   `c76c5dd34f80cebabb62a87706dbb7378981e3bacb30557a090dd26e5dcbd2b4`.)
   The model size (5M, 23M, or 79M) is inferred from the checkpoint; set
   `MAIA3_MODEL` (for example `maia3-79m`) to force it. Measured on a 4-core
   2009 Xeon, one move takes about 40 ms with 5M and 0.2 s (4 threads) to
   0.6 s (1 thread) with 79M; each engine process needs about 0.35 GB with 5M
   and 0.9 GB with 79M. With several bots and games at once, one thread per
   engine avoids the processes competing for the same cores. Restart the bots
   after changing `engine.env`.
3. Run the smoke test: `.venv/bin/python tests/smoke_engine.py`.

## Lichess accounts (manual, once per level)

1. Create a new Lichess account that has **never played a game**.
2. Create an API token with the `bot:play` scope.
3. Save the token as `tokens/<level>.token` (for example `tokens/1600.token`),
   then run `chmod 600 tokens/*`. The `tokens/` directory is ignored by git.
4. Upgrade the account to a BOT account, which is **irreversible**:
   `./upgrade-bot.sh 1600`. The script shows the account name and asks you to
   type it to confirm.
5. Write the profile: what the bot is, the level it imitates, that it is a
   university hobby project, and a contact.

## Running

- **Start.** `./run-bots.sh` (all levels) or `./run-bots.sh 1600`. Logs go to
  `logs/<level>.log`.
- **Stop.** `./stop-bots.sh` (all levels) or `./stop-bots.sh 1600`. Each bot
  runs in its own process group, and stopping signals the whole group:
  lichess-bot, its multiprocessing children (which hold the Lichess event
  stream), and engines. It interrupts first and terminates anything still
  running after 15 seconds (`STOP_WAIT_SECONDS`).
- **Clean up strays.** `./stop-bots.sh --all` also kills any stray process
  running this repository's Python environment.
- **Duplicates.** `run-bots.sh` refuses to start a level whose process group is
  still alive. Two consumers of the same token's event stream trigger Lichess
  rate limits (HTTP 429). After a 429, wait at least a minute before
  restarting.

## Running as a systemd user service

For unattended hosting, use the per-user systemd template instead of
`run-bots.sh`. Do not run both for the same level: two instances with one token
trigger Lichess rate limits.

1. Install the unit once: `./install-service.sh`. This writes
   `~/.config/systemd/user/maia960-bot@.service` for this repository's path.
2. Stop any instance started by `run-bots.sh`: `./stop-bots.sh 1600`.
3. Start and enable a level: `systemctl --user enable --now maia960-bot@1600`.
4. Enable lingering so the service survives logout and starts at boot:
   `loginctl enable-linger "$USER"`. This is a system setting and usually
   requires an administrator.

Management commands:

- **Status and logs.** `systemctl --user status maia960-bot@1600`,
  `journalctl --user -u maia960-bot@1600 -f`.
- **Stop or restart.** `systemctl --user stop maia960-bot@1600` (stops the
  whole process group, including children and engines), or
  `systemctl --user restart maia960-bot@1600` after changing a config.
- **Crash recovery.** The service restarts after crashes, waiting 120 seconds
  between attempts to respect Lichess rate limits.

## Network

- **Inbound.** None. lichess-bot is a client and listens on no port.
- **Outbound.** HTTPS (TCP 443) to `lichess.org`, plus DNS. The bot keeps
  long-lived streaming HTTP connections (one event stream and one per game);
  firewalls or proxies that cut idle connections can break them. Behind a
  proxy, set `HTTPS_PROXY`.
- **Setup only.** GitHub, PyPI, and the PyTorch wheel index.

## Resources

Each game runs its own engine process: about 310 MB of memory and about
20 ms of CPU per move (measured on a laptop CPU). With three bots at two
simultaneous games each, plan for about 2 GB of memory plus the lichess-bot
processes. CPU use is negligible.

## Licences

- **This repository.** GNU **Affero** General Public License v3 (AGPLv3; see
  `LICENSE`), because it uses Maia-3 code and weights, which are AGPLv3 (the
  `LICENSE` file of github.com/CSSLab/maia3).
- **Weights.** The fine-tuned weights are modified versions of the released
  Maia-3 5M and 79M checkpoints (Monroe et al., Chessformer, ICLR 2026).
- **Network use (AGPL section 13).** Lichess players interact with this
  program over a network, so they must be offered its source code. Publish this
  repository and link it in each bot's Lichess profile and greeting before the
  bots go public.
- **lichess-bot.** AGPLv3; used unmodified as a separate checkout.
