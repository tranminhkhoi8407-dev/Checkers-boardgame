import difflib

import pytest

MAX_DIFF_LINES = 40


def save_output(path, output):
    """Write what the program printed; a timeout hands over partial output as bytes."""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    path.write_text(output or "")


def assert_output_matches(output_path, expected_path):
    """Fail with a diff of the two files, so the first wrong line is easy to find."""
    output = output_path.read_text()
    expected = expected_path.read_text()
    if output == expected:
        return

    diff = list(difflib.unified_diff(
        expected.splitlines(),
        output.splitlines(),
        expected_path.name,
        output_path.name,
        lineterm="",
    ))
    shown = diff[:MAX_DIFF_LINES]
    if len(diff) > MAX_DIFF_LINES:
        shown.append(f"... {len(diff) - MAX_DIFF_LINES} more diff lines")
    pytest.fail(f"Output differs, see {output_path}\n" + "\n".join(shown), pytrace=False)
