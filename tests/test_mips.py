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

    Every fixture plays a game to the end: MARS crashes if a read syscall hits
    the end of stdin. MARS also prints one extra newline when the program exits,
    which is dropped so the saved file lines up with expected.txt.
    """
    output_path = test_dir / OUTPUT_FILE
    try:
        with open(test_dir / INPUT_FILE) as stdin:
            result = subprocess.run(
                ["java", "-jar", str(ROOT / "Mars45.jar"), "nc", str(ROOT / "src/main.asm")],
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


def assert_game(test_number):
    test_dir = ROOT / "tests" / f"test_{test_number:03d}"
    returncode = prepare_and_run(test_dir)
    assert_output_matches(test_dir / OUTPUT_FILE, test_dir / EXPECTED_FILE)
    assert returncode == 0


def test_mips_01():
    assert_game(1)


def test_mips_02():
    assert_game(2)


def test_mips_03():
    assert_game(3)


def test_mips_04():
    assert_game(4)


def test_mips_05():
    assert_game(5)
