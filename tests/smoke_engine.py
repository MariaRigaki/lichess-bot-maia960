"""Smoke test: drive the engine through python-chess as lichess-bot does.

Run: .venv/bin/python tests/smoke_engine.py
"""
from pathlib import Path
import random

import chess
import chess.engine

ROOT = Path(__file__).resolve().parents[1]


def play(engine, board, plies, rng):
    for _ in range(plies):
        if board.is_game_over():
            break
        result = engine.play(board, chess.engine.Limit(time=0.1), info=chess.engine.INFO_ALL)
        assert result.move in board.legal_moves, result.move
        board.push(result.move)
        if board.is_game_over():
            break
        board.push(rng.choice(list(board.legal_moves)))  # random opponent reply


def main():
    rng = random.Random(0)
    engine = chess.engine.SimpleEngine.popen_uci(str(ROOT / "run-engine.sh"))
    try:
        engine.configure({"SelfElo": 1200, "Temperature": "1.0"})
        engine.send_opponent_information(
            opponent=chess.engine.Opponent(name="tester", title=None, rating=1734, is_engine=False),
            engine_rating=1200)
        # Chess960: python-chess sets UCI_Chess960 automatically for chess960 boards.
        for setup in (0, 793, 857):
            board = chess.Board.from_chess960_pos(setup)
            play(engine, board, 40, rng)
            print(f"setup {setup}: {len(board.move_stack)} plies, final {board.fen()}")
        # Position where the engine side can castle (king g1, rook f1 queenside).
        board = chess.Board("bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/5RKR w HFhf - 0 1", chess960=True)
        engine.configure({"Temperature": "0"})
        move = engine.play(board, chess.engine.Limit(time=0.1)).move
        print("castle position move:", board.san(move), "castling:", board.is_castling(move))
        board = chess.Board()
        play(engine, board, 20, rng)
        print(f"standard: {len(board.move_stack)} plies OK")
        print("OK")
    finally:
        engine.quit()


if __name__ == "__main__":
    main()
