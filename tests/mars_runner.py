"""Shared helpers for test_rules.py and test_features.py: execute MARS with stdin."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARS = ROOT / "Mars45.jar"
MAIN_ASM = ROOT / "src" / "main.asm"
DRIVER_ASM = ROOT / "tests" / "unit" / "rules_driver.asm"


def run_mars(asm, lines, extra_args=(), program_args=()):
    """Feed a list of input lines or raw string to MARS stdin and return stdout."""
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
    """Map canonical square 1..32 -> (row, col), matching sq_to_rc in board_io.asm."""
    row = (square - 1) // 4
    col = 2 * ((square - 1) % 4) + (1 if row % 2 == 0 else 0)
    return row, col


def board_rows(pieces):
    """Build 8 compact board strings from {square: piece}; remaining dark squares are '0'."""
    rows = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
    for square, piece in pieces.items():
        r, c = square_rc(square)
        rows[r][c] = piece
    return ["".join(row) for row in rows]


def plain_board(pieces):
    """Render compact board matching classic terminal output (space-separated cells)."""
    return "".join(" ".join(row) + "\n" for row in board_rows(pieces))
