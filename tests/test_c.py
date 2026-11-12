import subprocess
from pathlib import Path

import pytest

from output_check import assert_output_matches, save_output

ROOT = Path(__file__).resolve().parents[1]
INPUT_FILE = "input.txt"
EXPECTED_FILE = "expected.txt"
OUTPUT_FILE = "output_c.txt"


def prepare_and_run(tmp_path, test_dir):
    """Feed the fixture's input.txt to stdin and save what the program prints."""
    output_path = test_dir / OUTPUT_FILE
    try:
        executable = tmp_path / "main"
        subprocess.run(["g++", "-o", str(executable), str(ROOT / "src/main.cpp")], check=True)
        with open(test_dir / INPUT_FILE) as stdin:
            result = subprocess.run(
                [str(executable)],
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

    save_output(output_path, result.stdout)
    print(result.stderr, end="")
    return result.returncode


def assert_game(tmp_path, test_number):
    test_dir = ROOT / "tests" / f"test_{test_number:03d}"
    returncode = prepare_and_run(tmp_path, test_dir)
    assert_output_matches(test_dir / OUTPUT_FILE, test_dir / EXPECTED_FILE)
    assert returncode == 0


def test_c_01(tmp_path):
    assert_game(tmp_path, 1)


def test_c_02(tmp_path):
    assert_game(tmp_path, 2)


def test_c_03(tmp_path):
    assert_game(tmp_path, 3)


def test_c_04(tmp_path):
    assert_game(tmp_path, 4)


def test_c_05(tmp_path):
    assert_game(tmp_path, 5)
