"""Kiểm thử chương trình chính (src/main.asm): phần bàn giao của Hậu và các tính năng thêm.

Phần bàn giao theo phân công:
  - khởi tạo đúng, Đen đi trước
  - nhập sai không làm hỏng chương trình
  - nước sai không mất lượt
  - đổi lượt đúng
  - thông báo thắng đúng (hết quân: test_mips 001/002/005, bị chặn: 003/004)
Tính năng thêm (mở bằng lệnh 0): menu, bàn cờ đẹp, xoay bàn, đánh số theo người
chơi, lỗi chi tiết, gợi ý, bắt buộc ăn, xin hòa, lịch sử, chơi lại, Bitmap Display.
"""
from pathlib import Path

from mars_runner import MAIN_ASM, ROOT, plain_board, run_mars

QUIT = ["0", "13"]                      # mở menu rồi chọn Quit
INVALID = "Not a valid move! Try again."
START = {s: "r" for s in range(1, 13)} | {s: "b" for s in range(21, 33)}


def play(*lines):
    return run_mars(MAIN_ASM, [str(x) for x in lines])


def turn_headers(out):
    return [line for line in out.splitlines() if line.endswith("'s turn.")]


def menu(*choices):
    """Mở menu, chọn lần lượt các mục rồi quay lại ván cờ."""
    return ["0", *map(str, choices), "0"]


# ------------------------- Phần bàn giao của Hậu -------------------------
def test_initial_board_and_black_moves_first():
    out = play(*QUIT)
    board = "".join(out.splitlines(keepends=True)[:8])
    assert board == plain_board(START)
    assert board.count("b") == 12 and board.count("r") == 12
    assert turn_headers(out) == ["Black's turn."]


def test_bad_input_does_not_crash():
    out = play("abc", "", "   ", "99999999999999999999", "-5", "17x", "21", "17", *QUIT)
    assert out.count(INVALID) == 3
    assert turn_headers(out) == ["Black's turn.", "Red's turn."]


def test_invalid_move_does_not_lose_turn():
    out = play("21", "13",          # sai luật
               "9", "13",           # quân của đối phương
               "18", "14",          # ô trống
               "21", "17", *QUIT)
    assert out.count(INVALID) == 3
    assert turn_headers(out) == ["Black's turn.", "Red's turn."]


def test_turns_alternate_after_each_valid_move():
    out = play("21", "17", "9", "13", "22", "18", "10", "15", *QUIT)
    assert turn_headers(out) == ["Black's turn.", "Red's turn.", "Black's turn.",
                                 "Red's turn.", "Black's turn."]


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


# --------------------------- Hiển thị -----------------------------------
def test_pretty_board():
    out = play(*menu(1), *QUIT)
    assert "Black (b, B = king): 12    Red (r, R = king): 12" in out
    assert "  |   | r |   | r |   | r |   | r |    |   | 1 |   | 2 |   | 3 |   | 4 |" in out
    assert "  | b |   | b |   | b |   | b |   |    |29 |   |30 |   |31 |   |32 |   |" in out


def test_rotation_and_red_numbering():
    # Đỏ thấy bàn xoay 180 độ và dùng số ô của mình: ô 24 của Đỏ = ô 9 thật
    out = play(*menu(2, 3), "21", "17", "24", "20", *QUIT)
    after_black = {**START, 17: "b"}
    del after_black[21]
    rotated = "".join(line[::-1] + "\n" for line in reversed(plain_board(after_black).splitlines()))
    assert rotated in out
    after_red = {**after_black, 13: "r"}
    del after_red[9]
    assert plain_board(after_red) in out
    assert turn_headers(out)[-1] == "Black's turn."


# --------------------------- Nhập liệu ----------------------------------
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


# --------------------------- Luật nâng cao --------------------------------
def test_forced_capture_in_game():
    moves = ["22", "18", "11", "15", "24", "20"]
    assert INVALID not in play(*moves, *QUIT)
    out = play(*menu(6, 4), *moves, "18", "11", *QUIT)
    assert "you must capture (forced capture rule)" in out
    assert "Captured Red's piece." in out


# --------------------------- Luồng game ----------------------------------
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


def test_bitmap_display_memory(tmp_path):
    dump = tmp_path / "bitmap.txt"
    run_mars(MAIN_ASM, [*menu(8), *QUIT],
             extra_args=["dump", "0x10040000-0x10044000", "HexText", str(dump)])
    pixels = [int(word, 16) for word in dump.read_text().split()]
    assert len(pixels) == 64 * 64
    assert pixels[0] == 0xF4F1EA                      # góc trái trên: ô trắng
    assert pixels[3 * 64 + 8 + 3] == 0xE02B20         # giữa ô số 1: quân Đỏ
    assert pixels[(7 * 8 + 3) * 64 + 3] == 0x17181A   # giữa ô số 29: quân Đen
    assert pixels[(4 * 8 + 3) * 64 + 8 + 3] == 0x64788A   # ô số 17 (hàng 4, cột 1): ô tối trống
    assert pixels[(4 * 8 + 3) * 64 + 3] == 0xF4F1EA       # hàng 4, cột 0: ô trắng
