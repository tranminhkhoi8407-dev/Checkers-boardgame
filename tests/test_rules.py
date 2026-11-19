"""Kiểm thử phần luật (rules.asm) bằng thế cờ dựng sẵn, qua tests/unit/rules_driver.asm.

Mỗi test nạp một thế cờ rồi gọi thẳng các hàm luật, nên kiểm tra được cả những
tình huống khó tạo ra bằng cách chơi từ đầu: phong vua rồi ăn lùi, bị chặn hết
nước, bắt buộc ăn, vua bay...
"""
from mars_runner import DRIVER_ASM, board_rows, plain_board, run_mars

BLACK, RED = 0, 1
INVALID, STEP, CAPTURE = 0, 1, 2
ERR_RANGE, ERR_EMPTY, ERR_NOT_YOURS, ERR_OCCUPIED = 1, 2, 3, 4
ERR_NOT_DIAGONAL, ERR_BACKWARD, ERR_TOO_FAR, ERR_NO_ENEMY = 5, 6, 7, 8
ERR_MUST_CAPTURE, ERR_CHAIN, ERR_BLOCKED = 9, 10, 11
OPT_FORCED, OPT_FLYING = 6, 7


class Driver:
    """Gom các lệnh cho rules_driver.asm rồi chạy một lần."""

    def __init__(self, pieces=None):
        self.lines = []
        if pieces is not None:
            self.lines += [1, *board_rows(pieces)]

    def option(self, k, v):
        self.lines += [8, k, v]
        return self

    def classify(self, s, d, side):
        self.lines += [2, s, d, side]
        return self

    def validate(self, s, d, side):
        self.lines += [3, s, d, side]
        return self

    def chain(self, s, d, side):
        self.lines += [4, s, d, side]
        return self

    def can_capture(self, s, side):
        self.lines += [5, s, side]
        return self

    def has_move(self, side):
        self.lines += [6, side]
        return self

    def do_move(self, s, d):
        self.lines += [7, s, d]
        return self

    def side_capture(self, side):
        self.lines += [9, side]
        return self

    def count(self, side):
        self.lines += [10, side]
        return self

    def run(self):
        # MARS in thêm một dòng trống khi chương trình kết thúc
        return run_mars(DRIVER_ASM, [*self.lines, 0]).rstrip("\n").splitlines()


def pair(type_, err=0):
    return f"{type_} {err}"


def test_initial_board_has_12_pieces_each():
    out = Driver().count(BLACK).count(RED).has_move(BLACK).has_move(RED).run()
    assert out == ["12", "12", "1", "1"]


def test_input_and_ownership_errors():
    out = (Driver({21: "b", 9: "r"})
           .classify(0, 17, BLACK)      # ô ngoài 1..32
           .classify(21, 40, BLACK)
           .classify(18, 14, BLACK)     # ô trống
           .classify(9, 13, BLACK)      # quân đối phương
           .run())
    assert out == [pair(INVALID, ERR_RANGE), pair(INVALID, ERR_RANGE),
                   pair(INVALID, ERR_EMPTY), pair(INVALID, ERR_NOT_YOURS)]


def test_pawn_moves_and_direction():
    out = (Driver({22: "b", 18: "b", 11: "r"})
           .classify(22, 17, BLACK)     # đi chéo lên 1 ô
           .classify(22, 18, BLACK)     # ô đích có quân
           .classify(22, 25, BLACK)     # quân thường không đi lùi
           .classify(22, 14, BLACK)     # không phải đường chéo... (22->14 thẳng cột)
           .classify(22, 13, BLACK)     # chéo 2 ô nhưng không có quân địch ở giữa
           .classify(11, 15, RED)       # Đỏ đi xuống
           .classify(11, 7, RED)        # Đỏ không đi lùi
           .run())
    assert out == [pair(STEP), pair(INVALID, ERR_OCCUPIED), pair(INVALID, ERR_BACKWARD),
                   pair(INVALID, ERR_NOT_DIAGONAL), pair(INVALID, ERR_NO_ENEMY),
                   pair(STEP), pair(INVALID, ERR_BACKWARD)]


def test_capture_removes_piece():
    pieces = {22: "b", 18: "r"}
    out = Driver(pieces).classify(22, 15, BLACK).do_move(22, 15).count(RED).run()
    assert out[0] == pair(CAPTURE)
    assert out[1] == "0"                                  # không phong vua
    assert "\n".join(out[2:10]) + "\n" == plain_board({15: "b"})
    assert out[10] == "0"


def test_promotion_both_sides():
    out = Driver({5: "b", 28: "r"}).do_move(5, 1).do_move(28, 32).run()
    assert out[0] == "1"
    assert out[9] == "1"
    assert "\n".join(out[10:18]) + "\n" == plain_board({1: "B", 32: "R"})


def test_king_moves_backward():
    out = Driver({18: "B", 15: "R"}).classify(18, 22, BLACK).classify(15, 10, RED).run()
    assert out == [pair(STEP), pair(STEP)]


def test_promotion_by_capture_then_chain_backward():
    """Hình 8 trong đề: 15x24 24x31 31x22 22x13, quân Đỏ phong vua ở 31 rồi ăn lùi."""
    pieces = {15: "r", 19: "b", 27: "b", 26: "b", 17: "b"}
    out = (Driver(pieces)
           .validate(15, 24, RED).do_move(15, 24).can_capture(24, RED)
           .chain(24, 31, RED).do_move(24, 31).can_capture(31, RED)
           .chain(31, 22, RED).do_move(31, 22).can_capture(22, RED)
           .chain(22, 13, RED).do_move(22, 13).can_capture(13, RED)
           .count(BLACK).has_move(BLACK)
           .run())
    boards = [out[i:i + 8] for i in (2, 13, 24, 35)]
    assert out[0] == pair(CAPTURE) and out[1] == "0" and out[10] == "1"
    assert out[11] == pair(CAPTURE) and out[12] == "1"          # phong vua ở 31
    assert out[21] == "1"                                       # vua mới ăn lùi tiếp được
    assert out[22] == pair(CAPTURE) and out[32] == "1"
    assert out[33] == pair(CAPTURE) and out[43] == "0"          # hết chuỗi ăn
    assert "\n".join(boards[3]) + "\n" == plain_board({13: "R"})
    assert out[44:] == ["0", "0"]


def test_chain_must_capture_with_same_piece():
    pieces = {18: "b", 15: "r", 10: "r", 23: "b", 19: "r"}
    out = (Driver(pieces)
           .validate(23, 16, BLACK)   # quân khác có nước ăn tới 16
           .chain(18, 16, BLACK)      # quân bị khóa ở 18 không thể chọn nước đó
           .chain(18, 14, BLACK)      # quân 18 cũng không được đi thường
           .chain(18, 9, BLACK)       # hoặc nhảy qua ô không có quân địch
           .chain(18, 10, BLACK)      # ô đích đang có quân
           .chain(18, 11, BLACK)      # nước ăn đúng của quân ở 18
           .run())
    assert out == [pair(CAPTURE), pair(INVALID, ERR_NOT_DIAGONAL), pair(INVALID, ERR_CHAIN),
                   pair(INVALID, ERR_NO_ENEMY), pair(INVALID, ERR_OCCUPIED), pair(CAPTURE)]


def test_blocked_side_has_no_moves():
    """Hình 9 trong đề: Đen còn quân nhưng không còn nước đi nào."""
    pieces = {1: "B", 2: "R", 5: "r", 6: "b", 10: "r"}
    out = Driver(pieces).has_move(BLACK).has_move(RED).count(BLACK).run()
    assert out == ["0", "1", "2"]


def test_forced_capture_rule():
    pieces = {22: "b", 18: "r", 24: "b"}
    out = (Driver(pieces)
           .validate(24, 20, BLACK)                     # tắt luật: đi thường vẫn được
           .option(OPT_FORCED, 1)
           .side_capture(BLACK)
           .validate(24, 20, BLACK)                     # bật luật: phải ăn
           .validate(22, 15, BLACK)
           .run())
    assert out == [pair(STEP), "1", pair(INVALID, ERR_MUST_CAPTURE), pair(CAPTURE)]


def test_flying_kings():
    # Đường chéo 29-25-22-18-15-11-8-4
    out = (Driver({29: "B", 15: "r"})
           .classify(29, 18, BLACK)                     # tắt: vua đi 1 ô
           .can_capture(29, BLACK)
           .option(OPT_FLYING, 1)
           .classify(29, 18, BLACK)                     # bật: đi xa trên đường trống
           .classify(29, 11, BLACK)                     # nhảy qua quân ở 15
           .classify(29, 4, BLACK)                      # đáp xa hơn phía sau
           .can_capture(29, BLACK)
           .do_move(29, 4)
           .run())
    assert out[:6] == [pair(INVALID, ERR_TOO_FAR), "0", pair(STEP), pair(CAPTURE),
                       pair(CAPTURE), "1"]
    assert "\n".join(out[7:15]) + "\n" == plain_board({4: "B"})


def test_flying_king_blocked_paths():
    out = (Driver({29: "B", 22: "b", 15: "r", 11: "r"}).option(OPT_FLYING, 1)
           .classify(22, 8, BLACK)                      # quân thường không bay
           .classify(29, 18, BLACK)                     # quân mình chắn ở 22
           .run())
    out2 = (Driver({29: "B", 18: "r", 15: "r"}).option(OPT_FLYING, 1)
            .classify(29, 11, BLACK)                    # không nhảy qua 2 quân
            .can_capture(29, BLACK)
            .run())
    assert out == [pair(INVALID, ERR_TOO_FAR), pair(INVALID, ERR_BLOCKED)]
    assert out2 == [pair(INVALID, ERR_BLOCKED), "0"]
