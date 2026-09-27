# Maia-3 Chess960 bots

Hobby deployment of a Maia-3 5M model fine-tuned on Lichess Chess960 blitz
games (65,536 training games, update 150,000 of the chess_960 research
project). Three Lichess BOT accounts imitate players rated about 1300, 1600,
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
- `engine/maia3_adapter.py`: board history, legal-move mapping, and Chess960
  castling-action adapter (from the research code).
- `run-engine.sh`: engine launcher, also usable from a GUI such as En Croissant.
- `bots/{1300,1600,1900}.yml`: lichess-bot configurations (casual games,
  Chess960 and standard, bullet to rapid (base 1–25 minutes, increment up to
  20 seconds), humans only, two simultaneous games per bot and one per opponent,
  no books or tablebases, no automatic draw offers or resignations). The model
  was trained on blitz moves made with at least 30 seconds on the clock, so
  bullet play imitates unhurried blitz rather than bullet habits.
- `run-bots.sh` / `stop-bots.sh`: start and stop one lichess-bot process per
  level.
- `tests/smoke_engine.py`: drives the engine through python-chess as
  lichess-bot does.

## Setup

1. Run `./setup.sh`. It creates `.venv/` (CPU PyTorch, pinned `maia3`,
   lichess-bot requirements) and clones
   [lichess-bot](https://github.com/lichess-bot-devs/lichess-bot) next to this
   repository if missing. Override its location with `LICHESS_BOT_DIR`.
2. Put the checkpoint at `checkpoints/maia3-960-ft65536-step150000.pt`
   (SHA-256 `14e89c7e0557a020d5424a9746dd1e1a5c8aee6f27d3220250482bad82dfcafa`),
   or set `MAIA3_CHECKPOINT`.
3. Run the smoke test: `.venv/bin/python tests/smoke_engine.py`.

## Lichess accounts (manual, once per level)

1. Create a new Lichess account that has **never played a game**.
2. Create an API token with the `bot:play` scope.
3. Save the token as `tokens/<level>.token` (for example `tokens/1600.token`),
   then run `chmod 600 tokens/*`. The `tokens/` directory is ignored by git.
4. Upgrade the account to a BOT account, which is **irreversible**:
   `cd ../lichess-bot && LICHESS_BOT_TOKEN="$(cat ../maia960-bot/tokens/1600.token)" ../maia960-bot/.venv/bin/python lichess-bot.py --config ../maia960-bot/.run/1600.yml -u`
   (run `./run-bots.sh 1600` once first to generate `.run/1600.yml`, or copy
   `bots/1600.yml` with `__ROOT__` replaced by the absolute path of this
   repository).
5. Write the profile: what the bot is, the level it imitates, that it is a
   university hobby project, and a contact.

## Running

- **Start.** `./run-bots.sh` (all levels) or `./run-bots.sh 1600`. Logs go to
  `logs/<level>.log`.
- **Stop.** `./stop-bots.sh` (all levels) or `./stop-bots.sh 1600`. It finds
  processes by config path, interrupts them, and terminates any still running
  after 15 seconds (`STOP_WAIT_SECONDS`). `run-bots.sh` refuses to start a level
  that is already running: two processes with the same token trigger Lichess
  rate limits (HTTP 429).

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
- **Weights.** The fine-tuned weights are a modified version of the released
  Maia-3 5M checkpoint (Monroe et al., Chessformer, ICLR 2026).
- **Network use (AGPL section 13).** Lichess players interact with this
  program over a network, so they must be offered its source code. Publish this
  repository and link it in each bot's Lichess profile and greeting before the
  bots go public.
- **lichess-bot.** AGPLv3; used unmodified as a separate checkout.
