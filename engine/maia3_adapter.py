"""Explicit, legal-move-complete inference adapter for the pinned Maia-3 code.

The orthodox-compatible mapping preserves the checkpoint's standard castling
indices when the king starts on e1/e8 and the castling rook on a1/a8 or h1/h8.
Other Chess960 castles use king-to-rook indices. Their learned semantics remain
an extrapolation; this adapter does not claim the pretrained model understands
those actions. Native king-to-rook indexing is available as a sensitivity check.
"""
from collections import deque
import hashlib
import json
from pathlib import Path

import chess
import torch
from maia3.dataset import tokenize_board, get_historical_tokens
from maia3.models import MAIA3Model
from maia3.uci import parse_args
from maia3.utils import get_all_possible_moves, mirror_move

MOVES = get_all_possible_moves()
MOVE_INDEX = {move: index for index, move in enumerate(MOVES)}


MODEL_NAMES = {
    "UofTCSSLab/Maia3-5M": "maia3-5m",
    "UofTCSSLab/Maia3-23M": "maia3-23m",
    "UofTCSSLab/Maia3-79M": "maia3-79m",
}


def config(checkpoint, device="cpu", model_name="maia3-5m"):
    return parse_args(["--model", model_name, "--checkpoint-path", str(checkpoint),
                       "--device", device, "--no-use-amp", "--use-uci-history",
                       "--temperature", "0"])


def load_checkpoint(directory, device="cpu", model_name=None):
    directory = Path(directory)
    manifest = json.loads((directory / "manifest.json").read_text())
    repo_id = manifest.get("repo_id")
    inferred = MODEL_NAMES[repo_id] if repo_id is not None else "maia3-5m"
    if model_name is not None and model_name != inferred:
        raise ValueError("Requested model name disagrees with checkpoint manifest")
    model_name = model_name or inferred
    path = directory / manifest["filename"]
    with path.open("rb") as source:
        actual = hashlib.file_digest(source, "sha256").hexdigest()
    if actual != manifest["sha256"]:
        raise ValueError("Checkpoint checksum mismatch")
    cfg = config(path, device, model_name)
    checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    state = checkpoint.get("model_state_dict", checkpoint)
    renamed = {key.replace("smolgen", "gab"): value for key, value in state.items()}
    if len(renamed) != len(state):
        raise ValueError("Checkpoint key renaming collision")
    model = MAIA3Model(cfg)
    model.load_state_dict(renamed, strict=True)
    return model.to(device).eval(), cfg, manifest


def action_key(board, move, convention="orthodox_compatible"):
    if convention not in ("orthodox_compatible", "native"):
        raise ValueError(f"Unknown castling convention: {convention}")
    key = move.uci()
    if convention == "orthodox_compatible" and board.chess960 and board.is_castling(move):
        rank = 0 if board.turn == chess.WHITE else 7
        if move.from_square == chess.square(4, rank) and move.to_square in (chess.square(0, rank), chess.square(7, rank)):
            target = chess.square(6 if board.is_kingside_castling(move) else 2, rank)
            key = chess.square_name(move.from_square) + chess.square_name(target)
    return key if board.turn == chess.WHITE else mirror_move(key)


def legal_actions(board, convention="orthodox_compatible"):
    """Return an injective mapping from policy indices to actual legal moves."""
    actions = {}
    for move in board.legal_moves:
        key = action_key(board, move, convention)
        if key not in MOVE_INDEX:
            raise ValueError(f"Legal move outside policy vocabulary: {key}")
        index = MOVE_INDEX[key]
        if index in actions:
            raise ValueError(f"Policy collision: {actions[index]} and {move}")
        actions[index] = move
    if len(actions) != board.legal_moves.count():
        raise ValueError("Incomplete legal-move coverage")
    return actions


def tokens_for(board, cfg):
    """Reconstruct actual recent history; orient each frame as in the reference."""
    replay = board.copy(stack=True)
    frames = []
    for _ in range(cfg.history):
        frames.append(tokenize_board(replay))
        if not replay.move_stack:
            break
        replay.pop()
    history = deque(reversed(frames), maxlen=cfg.history)
    return get_historical_tokens(history, cfg, 0, 0, 0, 0)


def log_policy(logits, board, convention="orthodox_compatible"):
    actions = legal_actions(board, convention)
    if not actions:
        raise ValueError("No legal actions in terminal position")
    indices = torch.tensor(list(actions), dtype=torch.long, device=logits.device)
    values = torch.log_softmax(logits.float()[indices], dim=0)
    if not torch.isfinite(values).all():
        raise ValueError("Non-finite legal log probabilities")
    if not torch.isclose(values.exp().sum(), values.new_tensor(1.0), atol=1e-6):
        raise ValueError("Policy does not normalize")
    return list(actions.values()), values
