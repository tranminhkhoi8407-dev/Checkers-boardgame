"""End-to-end feature and robustness tests for src/main.asm on MARS 4.5.

Core handoff deliverables verified:
  - accurate 12-vs-12 board initialization; Black moves first
  - malformed input and EOF never crash the simulator
  - invalid moves retain the active player's turn
  - proper turn alternation and chain-capture locking
  - accurate win announcements (elimination: 001/002/005; blockade: 003/004)
Extra features (menu option 0): pretty board, Red rotation, player-relative
numbering, detailed errors, move hints, forced capture, flying kings, draw
offers, move history, restart/replay, and MARS Bitmap Display rendering.
"""
import pytest

from mars_runner import MAIN_ASM, ROOT, plain_board, run_mars

QUIT = ["0", "13"]                      # open menu and select Quit
INVALID = "Not a valid move! Try again."
START = {s: "r" for s in range(1, 13)} | {s: "b" for s in range(21, 33)}
FLYING_KING_SETUP = (
    23, 19, 9, 14, 27, 23, 6, 9, 32, 27, 2, 6, 23, 18,
    14, 23, 32,  # Red double-captures 14x23 23x32 and crowns to king at 32.
    22, 18,      # Black steps onto diagonal 32-27-23-18-14.
)


def play(*lines, classic=True):
    return run_mars(MAIN_ASM, lines, program_args=("classic",) if classic else ())


def turn_headers(out):
    return [line for line in out.splitlines() if line.endswith("'s turn.")]


def menu(*choices):
    """Open menu, select each choice in order, and return to the game."""
    return ["0", *map(str, choices), "0"]


# ------------------------- Core Handoff Checks ---------------------------
def test_initial_board_and_black_moves_first():
    out = play(*QUIT)
    board = "".join(out.splitlines(keepends=True)[:8])
    assert board == plain_board(START)
    assert board.count("b") == 12 and board.count("r") == 12
    assert turn_headers(out) == ["Black's turn."]


def test_bad_input_does_not_crash():
    invalid_starts = ["abc", "", "   ", "99999999999999999999", "-5", "17x",
                      "33", "21\0x", "21" + " " * 300 + "x"]
    out = play(*invalid_starts, "21", "32x", "\t0021 ", "17\t", *QUIT)
    assert out.count("Enter starting square: " + INVALID) == len(invalid_starts)
    assert out.count(INVALID) == len(invalid_starts) + 1
    assert turn_headers(out) == ["Black's turn.", "Red's turn."]


@pytest.mark.parametrize(("input_text", "last_prompt"), [
    ("", "Enter starting square:"),
    ("21\r\n", "Enter landing square:"),
    ("0\n", "Your choice:"),
])
def test_end_of_input_exits_cleanly(input_text, last_prompt):
    out = run_mars(MAIN_ASM, input_text)
    assert out.rstrip().endswith(last_prompt)
    assert turn_headers(out) == ["Black's turn."]
    assert INVALID not in out and " wins!" not in out


def test_crlf_and_last_line_without_newline():
    out = run_mars(MAIN_ASM, "21" + " " * 61 + "\r\n17")
    assert INVALID not in out
    assert turn_headers(out) == ["Black's turn.", "Red's turn."]


def test_invalid_move_does_not_lose_turn():
    out = play("21", "13",          # illegal move geometry
               "9", "13",           # opponent's piece
               "18", "14",          # empty starting square
               "21", "17", *QUIT)
    assert out.count(INVALID) == 3
    assert turn_headers(out) == ["Black's turn.", "Red's turn."]
    after = {**START, 17: "b"}
    del after[21]
    assert plain_board(after) + "Red's turn.\n" in out


def test_turns_alternate_after_each_valid_move():
    out = play("21", "17", "9", "13", "22", "18", "10", "15", *QUIT)
    assert turn_headers(out) == ["Black's turn.", "Red's turn.", "Black's turn.",
                                 "Red's turn.", "Black's turn."]


def test_promotion_chain_keeps_turn_and_locks_piece():
    inputs = (ROOT / "tests" / "test_001" / "input.txt").read_text().split()
    assert inputs[31:35] == ["11", "2", "9", "18"]
    crowned = {1: "r", 2: "B", 3: "r", 4: "r", 6: "r", 8: "r", 12: "r", 13: "r",
               14: "r", 21: "b", 23: "b", **dict.fromkeys(range(26, 33), "b")}
    after_first_backward = {**crowned, 9: "B"}
    del after_first_backward[2], after_first_backward[6]
    after_last = {**after_first_backward, 18: "B"}
    del after_last[9], after_last[14]

    # Square 7 is a legal normal step for the king on 2, but chain continuation requires capture.
    prefix = plain_board(crowned) + "Chaining possible.\n"
    out = play(*inputs[:33], "7", "0", "abc", *inputs[33:35], *QUIT)
    before_chain, chain = out.split(prefix, 1)
    retries = ("Enter landing square: " + INVALID + "\n") * 3
    jumped = "Enter landing square: Captured Red's piece.\n"
    assert turn_headers(before_chain)[-1] == "Black's turn."
    assert chain.startswith(retries + jumped + plain_board(after_first_backward) +
                            "Chaining possible.\n" + jumped + plain_board(after_last) + "Red's turn.\n")

    # EOF mid-chain must also exit cleanly without hanging or throwing exceptions.
    assert play(*inputs[:33]).endswith(prefix + "Enter landing square: \n")


def test_blocked_player_loses_with_detailed_message():
    inputs = (ROOT / "tests" / "test_003" / "input.txt").read_text().split()
    out = play(*menu(4), *inputs)
    assert out.endswith("Red has no legal moves left.\nBlack wins!\n\n")


# ------------------------------ Menu -------------------------------------
def test_menu_lists_options_off_by_default_and_toggles():
    out = play("0", "1", "13")
    first, second = out.split("=============== MENU ===============")[1:3]
    assert first.count(" OFF\n") == 9
    assert "  1. Pretty board (frame + square numbers) ... ON\n" in second
    assert out.endswith("Goodbye!\n\n")


def test_unknown_menu_choice():
    out = play("0", "99", "abc", "13")
    assert out.count("Unknown choice.") == 2


# --------------------------- Display Modes -------------------------------
def test_pretty_board():
    out = play(*menu(1), *QUIT)
    assert "Black (b, B = king): 12    Red (r, R = king): 12" in out
    assert "  |   | r |   | r |   | r |   | r |    |   | 1 |   | 2 |   | 3 |   | 4 |" in out
    assert "  | b |   | b |   | b |   | b |   |    |29 |   |30 |   |31 |   |32 |   |" in out


def test_default_board_explains_controls_and_current_rules():
    out = play(*QUIT, classic=False)
    assert "CHECKERS\n" in out
    assert "Kings  Standard    |    First capture  Optional" in out
    assert "POSITION                             PLAYABLE SQUARES" in out
    assert "Black (b, B = king): 12    Red (r, R = king): 12" in out
    assert "0  Settings (at the starting-square prompt)" in out


def test_rotation_and_red_numbering():
    # Red sees a 180-degree rotated board with relative numbering: Red's 24 = canonical 9.
    out = play(*menu(2, 3), "21", "17", "24", "20", *QUIT)
    after_black = {**START, 17: "b"}
    del after_black[21]
    rotated = "".join(line[::-1] + "\n" for line in reversed(plain_board(after_black).splitlines()))
    assert rotated in out
    after_red = {**after_black, 13: "r"}
    del after_red[9]
    assert plain_board(after_red) in out
    assert turn_headers(out)[-1] == "Black's turn."


@pytest.mark.parametrize("rotation_options", [(2, 3), (3,)])
def test_numbered_board_agrees_with_red_input(rotation_options):
    out = play(*menu(1, *rotation_options), "21", "17", "24", "20", *QUIT)
    assert "[Red's view]" in out
    assert "  | r |   | r |   | r |   | r |   |    |29 |   |30 |   |31 |   |32 |   |" in out
    assert turn_headers(out) == ["Black's turn.", "Black's turn.", "Red's turn.", "Black's turn."]
    after_red = out.split("Red's turn.\n", 1)[1]
    assert "  | r |   | . |   | . |   | . |   |    |13 |   |14 |   |15 |   |16 |   |" in after_red


# --------------------------- Input & Hints -------------------------------
def test_detailed_errors():
    out = play(*menu(4), "abc", "18", "9", "21", "13", "21", "17", *QUIT)
    assert "Not a valid move! Please type a square number from 1 to 32. Try again." in out
    assert "Not a valid move! There is no piece on that starting square. Try again." in out
    assert "Not a valid move! That piece belongs to your opponent. Try again." in out
    assert "Not a valid move! Pieces can only move diagonally. Try again." in out


def test_hints_list_moves():
    out = play(*menu(5), "21", "17", *QUIT)
    assert "  Pieces that can move: 21 22 23 24" in out
    assert "  Possible landing squares: 17" in out


def test_hints_reject_piece_without_moves():
    out = play(*menu(5), "29", "21", "17", *QUIT)
    assert "  Possible landing squares: none - choose another piece." in out


# --------------------------- Advanced Rules ------------------------------
def test_forced_capture_in_game():
    moves = ["22", "18", "11", "15", "24", "20"]
    assert INVALID not in play(*moves, *QUIT)
    out = play(*menu(6, 4), *moves, "18", "11", *QUIT)
    assert "you must capture (forced capture rule)" in out
    assert "Captured Red's piece." in out


def test_flying_king_capture_is_required_and_hinted():
    out = play(*FLYING_KING_SETUP, *menu(4, 5, 6, 7), 32, 27, 32, 14, *QUIT)
    red_turn = out.rsplit("Red's turn.\n", 1)[1]
    assert "  Pieces that can move: 32\n" in red_turn
    assert red_turn.count("  Possible landing squares: 14\n") == 2
    assert red_turn.count("you must capture (forced capture rule)") == 1
    after = {1: "r", **dict.fromkeys(range(3, 13), "r"), 14: "R",
             **dict.fromkeys((19, 21, 24, 25, 26, 28, 29, 30, 31), "b")}
    assert "Captured Black's piece.\n" + plain_board(after) + "Black's turn.\n" in red_turn


def test_pretty_chain_identifies_the_piece_in_red_numbering():
    # Canonical 14x23 becomes 19x10 in Red's numbering; next chain landing is 1.
    out = play(*FLYING_KING_SETUP[:14], *menu(2, 3), 19, 10, 1, *QUIT, classic=False)
    assert "Chaining possible.\n  Continue with the piece on square 10.\n" in out
    assert "Captured Black's piece." in out.split("Chaining possible.", 1)[1]


# --------------------------- Match Flow ----------------------------------
def test_draw_needs_both_players():
    out = play(*menu(11), "21", "17", "0", "11")
    assert "Black offers a draw." in out
    assert "Black offers a draw. Open the menu (0) and choose 11 to accept" in out
    assert out.endswith("Both players agreed to a draw. Game over.\n\n")


def test_draw_offer_declined_by_moving():
    out = play(*menu(11), "21", "17", "9", "13", *QUIT)
    assert "Draw offer declined." in out


def test_history_uses_standard_notation():
    out = play("21", "17", "10", "14", "17", "10", "0", "10", "13")
    assert "  1. Black 21-17\n  2. Red 10-14\n  3. Black 17x10\n" in out


def test_restart_resets_board():
    out = play("21", "17", "0", "12", *QUIT)
    assert "Starting a new game..." in out
    tail = out.split("Starting a new game...\n")[1]
    assert tail.startswith(plain_board(START))
    assert turn_headers(tail)[0] == "Black's turn."


def test_play_again_after_game_ends():
    out = play(*menu(9, 11), "21", "17", "0", "11", "1", *QUIT)
    assert "Play again?" in out
    tail = out.split("Play again?")[1]
    assert "Starting a new game...\n" + plain_board(START) in tail


def test_pretty_board_reports_elimination_and_restarts_after_win():
    inputs = (ROOT / "tests" / "test_001" / "input.txt").read_text().split()
    out = play(*menu(9), *inputs, 1, *QUIT, classic=False)
    _, replay = out.split("Red has no pieces left.\nBlack wins!\n")
    assert "Play again?" in replay
    assert "Starting a new game..." in replay
    assert "Black (b, B = king): 12    Red (r, R = king): 12" in replay
    assert turn_headers(replay) == ["Black's turn."]


def test_bitmap_display_memory(tmp_path):
    dump = tmp_path / "bitmap.txt"
    run_mars(MAIN_ASM, [*menu(8), *FLYING_KING_SETUP, *QUIT],
             extra_args=["dump", "0x10040000-0x10044000", "HexText", str(dump)])
    pixels = [int(word, 16) for word in dump.read_text().split()]
    assert len(pixels) == 64 * 64
    assert pixels[0] == 0xEFE3CA                          # top-left: light square
    assert pixels[3 * 64 + 8 + 3] == 0xBE3448             # square 1: Red pawn
    assert pixels[(7 * 8 + 3) * 64 + 3] == 0x212C45       # square 29: Black pawn
    assert pixels[(4 * 8 + 3) * 64 + 8 + 3] == 0x567772   # square 17: empty dark square
    red_king_row = (7 * 8 + 3) * 64 + 6 * 8               # square 32: Red king
    assert pixels[red_king_row + 1] == 0xBE3448           # piece body
    assert pixels[red_king_row + 3] == 0xF1C972           # gold king crown
