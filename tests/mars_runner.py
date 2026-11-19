"""Tiện ích chung cho test_rules.py và test_features.py: chạy MARS với input cho sẵn."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARS = ROOT / "Mars45.jar"
MAIN_ASM = ROOT / "src" / "main.asm"
DRIVER_ASM = ROOT / "tests" / "unit" / "rules_driver.asm"


def run_mars(asm, lines, extra_args=(), program_args=()):
    """Nạp danh sách dòng hoặc chuỗi nguyên văn vào stdin rồi trả về stdout."""
    input_text = lines if isinstance(lines, str) else "".join(f"{line}\n" for line in lines)
    args = ["java", "-jar", str(MARS), "nc", "ae1", "se1", *extra_args, str(asm)]
    if program_args:
        args.extend(["pa", *program_args])
    result = subprocess.run(
        args,
        input=input_text.encode("utf-8"),
        capture_output=True,
        timeout=30,
    )
    stdout = result.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n")
    stderr = result.stderr.decode("utf-8", errors="replace")
    assert result.returncode == 0, stdout + stderr
    assert "Exception" not in stdout + stderr, stdout + stderr
    return stdout


def square_rc(square):
    """Ô 1..32 -> (hàng, cột), giống sq_to_rc trong board_io.asm."""
    row = (square - 1) // 4
    col = 2 * ((square - 1) % 4) + (1 if row % 2 == 0 else 0)
    return row, col


def board_rows(pieces):
    """Dựng 8 dòng bàn cờ từ {ô: ký tự}, các ô tối còn lại để trống ('0')."""
    rows = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
    for square, piece in pieces.items():
        r, c = square_rc(square)
        rows[r][c] = piece
    return ["".join(row) for row in rows]


def plain_board(pieces):
    """Bàn cờ theo đúng định dạng chương trình in ra (ký tự cách nhau bởi dấu cách)."""
    return "".join(" ".join(row) + "\n" for row in board_rows(pieces))
