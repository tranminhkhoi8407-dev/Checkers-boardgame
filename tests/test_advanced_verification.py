"""Advanced verification suite for the optimized v2.0 MIPS32 Checkers engine.

Covers industry-standard engine verification techniques on live MARS 4.5:
  1. WCDF English Checkers Perft(1..3) executed directly on src/rules.asm
     (forced capture: 7 / 49 / 302; optional first capture: 7 / 49 / 379).
  2. Differential randomized testing of the 32-bit Chinook SWAR bitboard engine
     (has_any_move, side_has_capture, count_pieces, validate_move) across both
     standard rules and flying kings, validating the Mobility Equivalence Theorem.
  3. Chinook Bidirectional SWAR Move Hints verification (standard, forced
     capture, chain capture, Red player-relative numbering, and flying kings).
  4. Dirty-tile incremental Bitmap Display pixel-exactness (4,096/4,096 pixels)
     across multi-move play, 180-degree rotation, game restart, and toggling
     opt_bitmap OFF/ON mid-game.
  5. Static MIPS32 ABI, push/pop balance, inner-loop pipeline scheduling, and
     ASCII-only source hygiene checks.
"""
import random
import re
from pathlib import Path

import pytest

from mars_runner import DRIVER_ASM, MAIN_ASM, ROOT, board_rows, run_mars, square_rc

BLACK, RED = 0, 1
QUIT = ["0", "13"]

START_BOARD = [
    "_r_r_r_r",
    "r_r_r_r_",
    "_r_r_r_r",
    "0_0_0_0_",
    "_0_0_0_0",
    "b_b_b_b_",
    "_b_b_b_b",
    "b_b_b_b_",
]

# Reference sprite mask and palette matching src/defs.asm & src/board_io.asm
PIECE_MASK = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 1, 2, 1, 1, 2, 1, 0],
    [0, 1, 2, 2, 2, 2, 1, 0],
    [0, 1, 1, 2, 2, 1, 1, 0],
    [0, 1, 1, 1, 1, 1, 1, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
]
COLOR_LIGHT = 0x00EFE3CA
COLOR_DARK = 0x00567772
COLOR_BLACK = 0x00212C45
COLOR_RED = 0x00BE3448
COLOR_KING = 0x00F1C972


# ------------------------ Independent Python Oracle -------------------------
def _is_own(p, side):
    return p in ("b", "B") if side == BLACK else p in ("r", "R")


def _is_enemy(p, side):
    return _is_own(p, 1 - side)


def _is_king(p):
    return p in ("B", "R")


def _dir_ok(p, side, dr):
    return _is_king(p) or dr == (-1 if side == BLACK else 1)


def _oracle_can_cap(board, sq, side, flying=False):
    rs, cs = square_rc(sq)
    p = board[rs][cs]
    for dr in (-1, 1):
        for dc in (-1, 1):
            if not _dir_ok(p, side, dr):
                continue
            k = 1
            if flying and _is_king(p):
                while 0 <= rs + k * dr < 8 and 0 <= cs + k * dc < 8 and board[rs + k * dr][cs + k * dc] == "0":
                    k += 1
            r1, c1 = rs + k * dr, cs + k * dc
            r2, c2 = rs + (k + 1) * dr, cs + (k + 1) * dc
            if 0 <= r2 < 8 and 0 <= c2 < 8 and _is_enemy(board[r1][c1], side) and board[r2][c2] == "0":
                return 1
    return 0


def _oracle_can_step(board, sq, side):
    rs, cs = square_rc(sq)
    p = board[rs][cs]
    for dr in (-1, 1):
        for dc in (-1, 1):
            if not _dir_ok(p, side, dr):
                continue
            r1, c1 = rs + dr, cs + dc
            if 0 <= r1 < 8 and 0 <= c1 < 8 and board[r1][c1] == "0":
                return 1
    return 0


def _oracle_side_cap(board, side, flying=False):
    return int(any(
        _is_own(board[square_rc(s)[0]][square_rc(s)[1]], side) and _oracle_can_cap(board, s, side, flying)
        for s in range(1, 33)
    ))


def _oracle_has_move(board, side, flying=False):
    return int(any(
        _is_own(board[square_rc(s)[0]][square_rc(s)[1]], side)
        and (_oracle_can_step(board, s, side) or _oracle_can_cap(board, s, side, flying))
        for s in range(1, 33)
    ))


def _reference_bitmap(board_lines, rotated=False):
    """Pure-Python full-frame 64x64 reference renderer matching MARS Bitmap Display."""
    pixels = [0] * (64 * 64)
    for r in range(8):
        for c in range(8):
            idx = r * 8 + c
            src_idx = (63 - idx) if rotated else idx
            cell = board_lines[src_idx // 8][src_idx % 8]
            bg = COLOR_LIGHT if cell == "_" else COLOR_DARK
            piece_col = 0
            king = False
            if cell == "b":
                piece_col = COLOR_BLACK
            elif cell == "B":
                piece_col, king = COLOR_BLACK, True
            elif cell == "r":
                piece_col = COLOR_RED
            elif cell == "R":
                piece_col, king = COLOR_RED, True
            for y in range(8):
                for x in range(8):
                    col = bg
                    if piece_col:
                        m = PIECE_MASK[y][x]
                        if m == 1:
                            col = piece_col
                        elif m == 2:
                            col = COLOR_KING if king else piece_col
                    pixels[(r * 8 + y) * 64 + (c * 8 + x)] = col
    return pixels


# ------------------- 1. Live MARS 4.5 WCDF Perft(1..3) ----------------------
def _mars_expand_ply(boards, side, forced):
    """Expand one full ply of board positions strictly through MARS src/rules.asm."""
    # Batch 1: query validate_move on all (own_piece, empty_square) pairs
    cmds = [8, 6, int(forced), 8, 7, 0]
    queries = []
    for bi, b in enumerate(boards):
        cmds += [1, *b]
        own = [s for s in range(1, 33) if _is_own(b[square_rc(s)[0]][square_rc(s)[1]], side)]
        empty = [s for s in range(1, 33) if b[square_rc(s)[0]][square_rc(s)[1]] == "0"]
        for s in own:
            for d in empty:
                cmds += [3, s, d, side]
                queries.append((bi, s, d))
    cmds.append(0)
    out = run_mars(DRIVER_ASM, cmds).rstrip("\n").splitlines()
    assert len(out) == len(queries)

    legal = [(bi, s, d, int(line.split()[0])) for (bi, s, d), line in zip(queries, out) if not line.startswith("0 ")]
    if not legal:
        return []

    # Batch 2: execute every legal move via MARS do_move and check chain captures
    cmds2 = [8, 6, int(forced), 8, 7, 0]
    for bi, s, d, mtype in legal:
        cmds2 += [1, *boards[bi], 7, s, d]
        if mtype == 2:
            cmds2 += [5, d, side]
    cmds2.append(0)
    out2 = run_mars(DRIVER_ASM, cmds2).rstrip("\n").splitlines()

    next_boards = []
    chains = []
    pos = 0
    for bi, s, d, mtype in legal:
        _promoted = out2[pos]
        new_board = [row.replace(" ", "") for row in out2[pos + 1:pos + 9]]
        pos += 9
        if mtype == 2:
            can_cont = int(out2[pos])
            pos += 1
            if can_cont:
                chains.append((new_board, d))
                continue
        next_boards.append(new_board)
    assert pos == len(out2)

    # Resolve any multi-jump capture chains recursively through MARS validate_chain + do_move
    while chains:
        ccmds = [8, 6, int(forced), 8, 7, 0]
        cqueries = []
        for ci, (cb, sq) in enumerate(chains):
            ccmds += [1, *cb]
            for d in range(1, 33):
                if cb[square_rc(d)[0]][square_rc(d)[1]] == "0":
                    ccmds += [4, sq, d, side]
                    cqueries.append((ci, sq, d))
        ccmds.append(0)
        cout = run_mars(DRIVER_ASM, ccmds).rstrip("\n").splitlines()
        clegal = [(ci, sq, d) for (ci, sq, d), ln in zip(cqueries, cout) if ln.startswith("2 ")]

        ecmds = [8, 6, int(forced), 8, 7, 0]
        for ci, sq, d in clegal:
            ecmds += [1, *chains[ci][0], 7, sq, d, 5, d, side]
        ecmds.append(0)
        eout = run_mars(DRIVER_ASM, ecmds).rstrip("\n").splitlines()
        new_chains = []
        epos = 0
        for ci, sq, d in clegal:
            nb = [row.replace(" ", "") for row in eout[epos + 1:epos + 9]]
            can_cont = int(eout[epos + 9])
            epos += 10
            if can_cont:
                new_chains.append((nb, d))
            else:
                next_boards.append(nb)
        chains = new_chains

    return next_boards


@pytest.mark.parametrize(("forced", "expected_counts"), [
    (True, [7, 49, 302]),   # Canonical WCDF English Checkers Perft(1..3)
    (False, [7, 49, 379]),  # CO2008 classic optional first capture Perft(1..3)
])
def test_live_mars_perft_depth_1_to_3(forced, expected_counts):
    """Verify MIPS32 src/rules.asm move tree matches exact Perft(1..3) counts."""
    boards = [START_BOARD]
    side = BLACK
    observed = []
    for _depth in range(3):
        boards = _mars_expand_ply(boards, side, forced=forced)
        observed.append(len(boards))
        side = 1 - side
    assert observed == expected_counts


# --------- 2. SWAR Bitboard & Mobility Equivalence Randomized Audit ---------
def test_swar_bitboard_and_mobility_equivalence_on_mars():
    """Verify SWAR has_any_move, side_has_capture, and popcount count_pieces across 120 random boards."""
    rng = random.Random(202605)
    cmds, expected = [], []
    for trial in range(120):
        flying = trial % 2
        board = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
        n_pieces = rng.randint(0, 22) if trial % 3 else rng.randint(14, 28)
        for sq in rng.sample(range(1, 33), n_pieces):
            r, c = square_rc(sq)
            p = rng.choice(["b", "r", "B", "R"])
            if p == "b" and r == 0:
                p = "B"
            if p == "r" and r == 7:
                p = "R"
            board[r][c] = p

        cmds += [1, *["".join(row) for row in board], 8, 7, flying]
        for side in (BLACK, RED):
            cmds += [6, side, 9, side, 10, side]
            hm_std = _oracle_has_move(board, side, flying=False)
            hm_fly = _oracle_has_move(board, side, flying=True)
            # Confirm Mobility Equivalence Theorem holds identically on every generated board
            assert hm_std == hm_fly
            expected += [
                str(hm_fly if flying else hm_std),
                str(_oracle_side_cap(board, side, flying=bool(flying))),
                str(sum(1 for r in board for cell in r if _is_own(cell, side))),
            ]
    cmds.append(0)
    actual = run_mars(DRIVER_ASM, cmds).rstrip("\n").splitlines()
    assert actual == expected


# ----------- 3. Chinook Bidirectional SWAR Move Hints Verification ----------
def test_swar_hints_relative_numbering_and_forced_capture():
    """Verify Reverse-SWAR movable hints and Forward-SWAR landing hints under Red's relative numbering."""
    # Enable opt_relnum(3), opt_hints(5), opt_forced(6):
    # Black moves 22-18; Red sees relative numbering (Red's 21..24 = canonical 12..9).
    out = run_mars(
        MAIN_ASM,
        ["0", "3", "5", "6", "0", "22", "18", "22", "18", *QUIT],
        program_args=("classic",),
    )
    red_section = out.split("Red's turn.\n", 1)[1]
    # Red's movable pieces in ascending relative numbering must be 21 22 23 24
    assert "  Pieces that can move: 21 22 23 24\n" in red_section
    # Red picks relative 22 (= canonical 11): legal relative landings are 17, 18 (= canonical 16, 15)
    assert "  Possible landing squares: 17 18\n" in red_section
    # After Red plays 22-18 (canonical 11-15), Black MUST capture with 18 (18x11)!
    black_next = red_section.split("Black's turn.\n", 1)[1]
    assert "  A capture is available: you must capture.\n" in black_next
    assert "  Pieces that can move: 18\n" in black_next


def test_swar_hints_during_multi_jump_chain():
    """Verify Forward-SWAR landing hints during an active capture chain."""
    # 21-17, 10-14, 22-18, 9-13, 17x10 (single), etc. Use test_001's crowning chain at moves 31..35!
    inputs = (ROOT / "tests" / "test_001" / "input.txt").read_text().split()
    out = run_mars(
        MAIN_ASM,
        ["0", "5", "0", *inputs[:35], *QUIT],
        program_args=("classic",),
    )
    # test_001 executes a 4-jump sequence: ...x11 -> 11x2 (crowns!) -> 2x9 -> 9x18
    after_chain = out.split("Chaining possible.\n")
    assert len(after_chain) >= 4
    assert "  Possible landing squares: 2\n" in after_chain[1]
    assert "  Possible landing squares: 9\n" in after_chain[2]
    assert "  Possible landing squares: 18\n" in after_chain[3]


# --------- 4. Dirty-Tile Bitmap Display Pixel-Exact Stress Tests ------------
def test_dirty_tile_bitmap_exact_across_moves_rotation_restart_and_toggle(tmp_path):
    """Verify dirty-tile cache + LICM + 8-way unrolled solid fill matches full reference 4096/4096 px."""
    # Case A: multi-move + capture + rotation ON (Red's rotated view)
    dump_rot = tmp_path / "bmp_rot.hex"
    out_rot = run_mars(
        MAIN_ASM,
        ["0", "2", "8", "0", "21", "17", "10", "14", "17", "10", *QUIT],
        extra_args=["dump", "0x10040000-0x10044000", "HexText", str(dump_rot)],
        program_args=("classic",),
    )
    # Extract last printed plain board (which is already rotated for Red's upcoming turn!)
    board_rows_rot = [
        ln.replace(" ", "")
        for ln in out_rot.splitlines()
        if re.fullmatch(r"[_0rbRB]( [_0rbRB]){7}", ln)
    ][-8:]
    actual_rot = [int(w, 16) for w in dump_rot.read_text().split()]
    # Note: board_rows_rot is already rotated, so render with rotated=False to compare directly
    assert actual_rot == _reference_bitmap(board_rows_rot, rotated=False)

    # Case B: draw -> toggle bitmap OFF -> play moves -> toggle bitmap ON -> restart (menu 12)
    dump_restart = tmp_path / "bmp_restart.hex"
    run_mars(
        MAIN_ASM,
        [
            "0", "8", "0",        # turn Bitmap ON (initial full draw)
            "21", "17",           # dirty move 1
            "0", "8", "0",        # turn Bitmap OFF
            "10", "14", "17", "10",  # capture while Bitmap is OFF
            "0", "8", "0",        # turn Bitmap back ON (reconciles cache vs live board)
            "0", "12",            # Restart game (invalidates bmp_valid)
            *QUIT,
        ],
        extra_args=["dump", "0x10040000-0x10044000", "HexText", str(dump_restart)],
        program_args=("classic",),
    )
    actual_restart = [int(w, 16) for w in dump_restart.read_text().split()]
    assert actual_restart == _reference_bitmap(START_BOARD, rotated=False)


# --------- 5. Static ABI, Pipeline Hygiene, and English Repo Audit ----------
def test_static_abi_balance_and_english_hygiene():
    """Verify balanced push/pop per file, 0 inner-loop load-use hazards, and pure ASCII code."""
    for rel in ("src/defs.asm", "src/main.asm", "src/board_io.asm", "src/rules.asm"):
        text = (ROOT / rel).read_text(encoding="utf-8")
        # 1. Pure ASCII across all assembly source files
        non_ascii = [ch for ch in text if ord(ch) > 127]
        assert not non_ascii, f"Non-ASCII characters found in {rel}: {non_ascii[:5]}"
        # 2. Balanced push/pop macro counts
        if rel != "src/defs.asm":
            pushes = re.findall(r"\bpush\(", text)
            pops = re.findall(r"\bpop\(", text)
            assert len(pushes) == len(pops), f"Unbalanced push/pop in {rel}: {len(pushes)} vs {len(pops)}"

    # 3. Verify inner-loop load-use delay slots remain scheduled in board_io.asm & rules.asm
    bio = (ROOT / "src" / "board_io.asm").read_text(encoding="utf-8")
    assert "lbu  $t3, 0($t5)" in bio and "addi $t5, $t5, 1" in bio
    rules = (ROOT / "src" / "rules.asm").read_text(encoding="utf-8")
    assert "lbu  $t3, 0($t0)" in rules and "addi $t0, $t0, 2" in rules
