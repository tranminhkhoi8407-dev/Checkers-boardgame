import subprocess
from pathlib import Path

import pytest

from output_check import assert_output_matches, save_output

ROOT = Path(__file__).resolve().parents[1]
INPUT_FILE = "input.txt"
EXPECTED_FILE = "expected.txt"
OUTPUT_FILE = "output_mips.txt"


def prepare_and_run(test_dir):
    """Feed the fixture's input.txt to MARS through stdin and save its output.

    Every fixture plays a game to the end. MARS prints one extra newline when
    the program exits, which is dropped to line up with expected.txt.
    """
    output_path = test_dir / OUTPUT_FILE
    try:
        with open(test_dir / INPUT_FILE) as stdin:
            result = subprocess.run(
                ["java", "-jar", str(ROOT / "Mars45.jar"), "nc", "ae1", "se1",
                 str(ROOT / "src/main.asm"), "pa", "classic"],
                stdin=stdin,
                capture_output=True,
                text=True,
                timeout=10,
            )
    except subprocess.TimeoutExpired as exc:
        save_output(output_path, exc.stdout)
        pytest.fail(f"Program execution timed out, partial output in {output_path}")
    except Exception as exc:
        pytest.fail(f"Failed to run program: {exc}")

    output = result.stdout
    save_output(output_path, output[:-1] if output.endswith("\n\n") else output)
    print(result.stderr, end="")
    return result.returncode


@pytest.mark.parametrize(("test_number", "winner", "losing_piece", "remaining"), [
    (1, "Black", "r", 0),
    (2, "Red", "b", 0),
    (3, "Black", "r", 1),
    (4, "Red", "b", 3),
    (5, "Black", "r", 0),
])
def test_mips_games(test_number, winner, losing_piece, remaining):
    test_dir = ROOT / "tests" / f"test_{test_number:03d}"
    returncode = prepare_and_run(test_dir)
    assert_output_matches(test_dir / OUTPUT_FILE, test_dir / EXPECTED_FILE)
    assert returncode == 0
    lines = (test_dir / OUTPUT_FILE).read_text().splitlines()
    assert lines[-1] == f"{winner} wins!"
    final_board = "\n".join(lines[-9:-1]).split()
    assert sum(cell.lower() == losing_piece for cell in final_board) == remaining
