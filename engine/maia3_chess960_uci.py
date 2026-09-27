"""Minimal UCI engine for (fine-tuned) Maia-3 weights with Chess960 support.

Uses the same board history, rating inputs, and Chess960 castling-action
adapter as the RQ3 training and evaluation code. No search: each move is
chosen from the policy over legal moves, either sampled with a temperature
or, at temperature 0, the most likely move.

Example:
    .venv/bin/python engine/maia3_chess960_uci.py \
        --checkpoint checkpoints/maia3-960-ft65536-step150000.pt --elo 1600

The standard UCI option UCI_Opponent (sent by lichess-bot through python-chess)
sets OppoElo to the opponent's rating for each game.
"""

import argparse
import os
import sys

import chess
import torch
from maia3.models import MAIA3Model

from maia3_adapter import config, log_policy, tokens_for

NAME = "Maia3-960"


def load_model(checkpoint, device):
    cfg = config(checkpoint, device)
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    state = state.get("model_state_dict", state)
    state = {key.replace("smolgen", "gab"): value for key, value in state.items()}
    model = MAIA3Model(cfg)
    model.load_state_dict(state, strict=True)
    return model.to(device).eval(), cfg


def nonstandard_castling_field(fen):
    fields = fen.split()
    return len(fields) > 2 and any(char not in "KQkq-" for char in fields[2])


def is_chess960_position(board):
    """True when castling rights imply a non-orthodox king or rook square."""
    rights = board.clean_castling_rights()
    if rights & ~(chess.BB_A1 | chess.BB_H1 | chess.BB_A8 | chess.BB_H8):
        return True
    for color, home in ((chess.WHITE, chess.E1), (chess.BLACK, chess.E8)):
        if rights & board.occupied_co[color] and board.king(color) != home:
            return True
    return False


def parse_move(board, text):
    """Accept king-to-rook (Chess960) and king-destination castling notation."""
    try:
        return board.parse_uci(text)
    except ValueError:
        for move in board.legal_moves:
            if board.is_castling(move) and text in (board.uci(move, chess960=False),
                                                    board.uci(move, chess960=True)):
                return move
        raise


class Engine:
    def __init__(self, args):
        self.args = args
        self.model = None
        self.cfg = None
        self.chess960 = False  # UCI_Chess960 option as set by the GUI
        self.game960 = False   # Chess960 rules for the current position
        log_path = os.environ.get("MAIA3_UCI_LOG")
        self.log = open(log_path, "a", buffering=1) if log_path else None
        self.self_elo = args.elo
        self.oppo_elo = args.elo
        self.temperature = args.temperature
        self.board = chess.Board()

    def send(self, line):
        if self.log:
            self.log.write(f"<< {line}\n")
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    def ensure_model(self):
        if self.model is None:
            print(f"loading {self.args.checkpoint}", file=sys.stderr, flush=True)
            self.model, self.cfg = load_model(self.args.checkpoint, self.args.device)

    def cmd_uci(self):
        self.send(f"id name {NAME}")
        self.send("id author chess_960 project (Maia-3 fine-tune)")
        self.send("option name UCI_Chess960 type check default false")
        self.send(f"option name SelfElo type spin default {self.args.elo} min 500 max 3000")
        self.send(f"option name OppoElo type spin default {self.args.elo} min 500 max 3000")
        self.send(f"option name Temperature type string default {self.args.temperature}")
        self.send("option name UCI_Opponent type string default none")
        self.send("uciok")

    def cmd_setoption(self, line):
        tokens = line.split()
        if "name" not in tokens:
            return
        name_end = tokens.index("value") if "value" in tokens else len(tokens)
        name = " ".join(tokens[tokens.index("name") + 1:name_end]).lower()
        value = " ".join(tokens[name_end + 1:]) if "value" in tokens else ""
        try:
            if name == "uci_chess960":
                self.chess960 = value.lower() == "true"
            elif name == "selfelo":
                self.self_elo = int(value)
            elif name == "oppoelo":
                self.oppo_elo = int(value)
            elif name == "temperature":
                self.temperature = max(0.0, float(value))
            elif name == "uci_opponent":
                # Format: <title|none> <rating|none> <computer|human> <name>
                parts = value.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    self.oppo_elo = int(parts[1])
        except ValueError:
            print(f"ignoring invalid option value: {line}", file=sys.stderr, flush=True)

    def cmd_position(self, line):
        tokens = line.split()
        moves = tokens[tokens.index("moves") + 1:] if "moves" in tokens else []
        if len(tokens) > 1 and tokens[1] == "fen":
            end = tokens.index("moves") if "moves" in tokens else len(tokens)
            fen = " ".join(tokens[2:end])
            board = chess.Board(fen, chess960=True)
            self.game960 = (self.chess960 or nonstandard_castling_field(fen) or
                            is_chess960_position(board))
        else:
            board = chess.Board(chess960=True)
            self.game960 = self.chess960
        board.chess960 = self.game960
        for text in moves:
            try:
                board.push(parse_move(board, text))
            except ValueError:
                print(f"illegal or unparsable move {text}; position truncated",
                      file=sys.stderr, flush=True)
                break
        self.board = board

    @torch.no_grad()
    def cmd_go(self):
        self.ensure_model()
        if self.board.is_game_over(claim_draw=False) or not any(self.board.legal_moves):
            self.send("bestmove 0000")
            return
        tokens = tokens_for(self.board, self.cfg).unsqueeze(0).to(self.args.device)
        own = torch.tensor([float(self.self_elo)], device=self.args.device)
        opp = torch.tensor([float(self.oppo_elo)], device=self.args.device)
        logits = self.model(tokens, own, opp)[0][0]
        moves, logp = log_policy(logits, self.board)
        probs = logp.exp()
        if self.temperature <= 0:
            index = int(torch.argmax(logp))
        else:
            index = int(torch.multinomial(torch.softmax(logp / self.temperature, dim=0), 1))
        move = moves[index]
        uci = self.board.uci(move, chess960=self.game960)
        top = torch.argsort(probs, descending=True)[:3].tolist()
        summary = " ".join(f"{self.board.san(moves[i])}={100 * float(probs[i]):.1f}%" for i in top)
        # No score is reported: the policy has no evaluation, and a placeholder
        # score would trigger GUI or lichess-bot draw and resignation rules.
        self.send(f"info depth 1 nodes 1 pv {uci}")
        self.send(f"info string policy {summary} (SelfElo {self.self_elo}, OppoElo {self.oppo_elo})")
        self.send(f"bestmove {uci}")

    def loop(self):
        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            if self.log:
                self.log.write(f">> {line}\n")
            command = line.split()[0]
            if command == "uci":
                self.cmd_uci()
            elif command == "isready":
                self.ensure_model()
                self.send("readyok")
            elif command == "setoption":
                self.cmd_setoption(line)
            elif command == "ucinewgame":
                self.board = chess.Board()
                self.game960 = self.chess960
            elif command == "position":
                self.cmd_position(line)
            elif command == "go":
                self.cmd_go()
            elif command == "quit":
                break


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", required=True,
                        help="Maia-3 5M state dict (fine-tuned step-*.pt or released checkpoint file)")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--elo", type=int, default=1600)
    parser.add_argument("--temperature", type=float, default=1.0)
    args = parser.parse_args()
    torch.set_num_threads(2)
    Engine(args).loop()


if __name__ == "__main__":
    main()
