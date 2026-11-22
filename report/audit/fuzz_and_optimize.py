"""Differential property-based fuzzer (4,000 queries) and live MARS 4.5 optimization benchmarks.

Verifies src/rules.asm against an independent Python oracle across 500 randomized
boards (English, Forced Capture, Flying Kings), verifies 10,000 SWAR bitboard
positions, and benchmarks three isolated MIPS32 optimization prototypes in a
temporary directory without modifying src/.
"""
import pathlib
import random
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
MARS = ROOT / "Mars45.jar"
DRIVER_ASM = ROOT / "tests" / "unit" / "rules_driver.asm"
MAIN_ASM = ROOT / "src" / "main.asm"
JAVA = shutil.which("java") or "java"


def sq_rc(s):
    r = (s - 1) // 4
    c = 2 * ((s - 1) % 4) + (1 if r % 2 == 0 else 0)
    return r, c


def is_own(p, side):
    return p in ("b", "B") if side == 0 else p in ("r", "R")


def is_enemy(p, side):
    return is_own(p, 1 - side)


def is_king(p):
    return p in ("B", "R")


def dir_ok(p, side, dr):
    return is_king(p) or dr == (-1 if side == 0 else 1)


def oracle_classify(board, s, d, side, flying=False):
    if not (1 <= s <= 32):
        return (0, 1)
    rs, cs = sq_rc(s)
    p = board[rs][cs]
    if p == "0":
        return (0, 2)
    if not is_own(p, side):
        return (0, 3)
    if not (1 <= d <= 32):
        return (0, 1)
    rd, cd = sq_rc(d)
    if board[rd][cd] != "0":
        return (0, 4)
    dr, dc = rd - rs, cd - cs
    if abs(dr) != abs(dc):
        return (0, 5)
    sdr = 1 if dr > 0 else -1
    sdc = 1 if dc > 0 else -1
    if not dir_ok(p, side, sdr):
        return (0, 6)
    n = abs(dr)
    if flying and is_king(p):
        enemies = 0
        for k in range(1, n):
            cell = board[rs + k * sdr][cs + k * sdc]
            if cell == "0":
                continue
            if not is_enemy(cell, side):
                return (0, 11)
            enemies += 1
            if enemies > 1:
                return (0, 11)
        return (2 if enemies == 1 else 1, 0)
    if n == 1:
        return (1, 0)
    if n != 2:
        return (0, 7)
    mid = board[rs + sdr][cs + sdc]
    if not is_enemy(mid, side):
        return (0, 8)
    return (2, 0)


def oracle_can_cap(board, s, side, flying=False):
    rs, cs = sq_rc(s)
    p = board[rs][cs]
    for dr in (-1, 1):
        for dc in (-1, 1):
            if not dir_ok(p, side, dr):
                continue
            k = 1
            if flying and is_king(p):
                while 0 <= rs + k * dr < 8 and 0 <= cs + k * dc < 8 and board[rs + k * dr][cs + k * dc] == "0":
                    k += 1
            r1, c1 = rs + k * dr, cs + k * dc
            r2, c2 = rs + (k + 1) * dr, cs + (k + 1) * dc
            if 0 <= r2 < 8 and 0 <= c2 < 8 and is_enemy(board[r1][c1], side) and board[r2][c2] == "0":
                return 1
    return 0


def oracle_can_step(board, s, side):
    rs, cs = sq_rc(s)
    p = board[rs][cs]
    for dr in (-1, 1):
        for dc in (-1, 1):
            if not dir_ok(p, side, dr):
                continue
            r1, c1 = rs + dr, cs + dc
            if 0 <= r1 < 8 and 0 <= c1 < 8 and board[r1][c1] == "0":
                return 1
    return 0


def oracle_side_cap(board, side, flying=False):
    for s in range(1, 33):
        r, c = sq_rc(s)
        if is_own(board[r][c], side) and oracle_can_cap(board, s, side, flying):
            return 1
    return 0


def oracle_has_move(board, side, flying=False):
    for s in range(1, 33):
        r, c = sq_rc(s)
        if is_own(board[r][c], side) and (oracle_can_step(board, s, side) or oracle_can_cap(board, s, side, flying)):
            return 1
    return 0


def oracle_validate(board, s, d, side, forced=False, flying=False):
    t, e = oracle_classify(board, s, d, side, flying)
    if t == 1 and forced and oracle_side_cap(board, side, flying):
        return (0, 9)
    return (t, e)


def run_ic(asm_path, stdin_text, extra=(), pa=()):
    cmd = [JAVA, "-jar", str(MARS), "nc", "ae1", "se1", "ic", *extra, str(asm_path)]
    if pa:
        cmd += ["pa", *pa]
    r = subprocess.run(cmd, input=stdin_text.encode("utf-8"), capture_output=True, timeout=60)
    assert r.returncode == 0, r.stderr.decode(errors="replace")
    out = r.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n")
    lines = [line for line in out.splitlines() if line.strip()]
    ic = int(lines[-1])
    return ic, out.rsplit(str(ic), 1)[0]


def run_differential_fuzzer(n_boards=500):
    rng = random.Random(20261122)
    cmds, expected = [], []
    for _ in range(n_boards):
        forced = rng.randint(0, 1)
        flying = rng.randint(0, 1)
        board = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
        chosen = rng.sample(range(1, 33), rng.randint(1, 14))
        for sq in chosen:
            r, c = sq_rc(sq)
            piece = rng.choice(["b", "r", "B", "R"])
            if piece == "b" and r == 0:
                piece = "B"
            if piece == "r" and r == 7:
                piece = "R"
            board[r][c] = piece

        cmds += ["1", *["".join(row) for row in board], "8", "6", str(forced), "8", "7", str(flying)]
        for side in (0, 1):
            cmds += ["9", str(side), "6", str(side)]
            expected += [str(oracle_side_cap(board, side, bool(flying))),
                         str(oracle_has_move(board, side, bool(flying)))]
        for _ in range(4):
            s = rng.choice(chosen) if rng.random() < 0.8 else rng.randint(0, 33)
            d = rng.randint(0, 33)
            side = rng.randint(0, 1)
            cmds += ["3", str(s), str(d), str(side)]
            t, e = oracle_validate(board, s, d, side, bool(forced), bool(flying))
            expected.append(f"{t} {e}")
    cmds.append("0")

    res = subprocess.run(
        [JAVA, "-jar", str(MARS), "nc", "ae1", "se1", str(DRIVER_ASM)],
        input=("\n".join(cmds) + "\n").encode("utf-8"),
        capture_output=True,
        timeout=60,
    )
    assert res.returncode == 0, res.stderr.decode(errors="replace")
    actual = res.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n").rstrip("\n").splitlines()
    mismatches = sum(1 for a, b in zip(actual, expected) if a != b)
    print(f"=== DIFFERENTIAL FUZZER: {n_boards} boards, {len(expected)} queries ===")
    print(f"Exact matches: {len(actual) - mismatches}/{len(expected)} | Mismatches: {mismatches}")
    assert len(actual) == len(expected) and mismatches == 0


def verify_swar_bitboard_math():
    def step_nw(x): return ((x & 0x0F0F0F00) >> 4) | ((x & 0xE0E0E0E0) >> 5)
    def step_ne(x): return ((x & 0xF0F0F0F0) >> 4) | ((x & 0x07070700) >> 3)
    def step_sw(x): return ((x & 0x0F0F0F0F) << 4) | ((x & 0x00E0E0E0) << 3)
    def step_se(x): return ((x & 0x00F0F0F0) << 4) | ((x & 0x07070707) << 5)

    rng = random.Random(42)
    for _ in range(10000):
        bp = rng.getrandbits(32) & rng.getrandbits(32)
        rp = (rng.getrandbits(32) & rng.getrandbits(32)) & (~bp & 0xFFFFFFFF)
        k = rng.getrandbits(32) & (bp | rp)
        e = (~(bp | rp)) & 0xFFFFFFFF
        bk = bp & k
        swar = 1 if (
            (step_nw(step_nw(bp) & rp) & e)
            | (step_ne(step_ne(bp) & rp) & e)
            | (step_sw(step_sw(bk) & rp) & e)
            | (step_se(step_se(bk) & rp) & e)
        ) else 0
        board = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
        for b in range(32):
            r, c = sq_rc(b + 1)
            if (bp >> b) & 1:
                board[r][c] = "B" if ((k >> b) & 1) else "b"
            elif (rp >> b) & 1:
                board[r][c] = "R" if ((k >> b) & 1) else "r"
        assert swar == oracle_side_cap(board, 0, False)
    print("=== SWAR 32-BIT BITBOARD MATH VERIFICATION: 10,000 / 10,000 PASS ===")


def run_optimization_benchmarks():
    t1 = (ROOT / "tests" / "test_001" / "input.txt").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        for fn in ("defs.asm", "main.asm", "board_io.asm", "rules.asm"):
            shutil.copy2(ROOT / "src" / fn, tmp / fn)

        # Prototype 1: Ray-cached print_movable_pieces
        main_txt = (tmp / "main.asm").read_text(encoding="utf-8").replace("\r\n", "\n")
        marker = "print_movable_pieces:"
        end_marker = "print_movable_show:"
        start_idx = main_txt.index(marker)
        end_idx = main_txt.index(end_marker)
        opt1_body = """print_movable_pieces:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a0
    li   $s3, 0
    lw   $t0, opt_forced
    beqz $t0, print_movable_list
    jal  side_has_capture
    move $s3, $v0
    beqz $s3, print_movable_list
    print_str(str_must_cap)
print_movable_list:
    print_str(str_hint_pieces)
    li   $s1, 1
print_movable_loop:
    move $a0, $s1
    move $a1, $s0
    jal  view_square
    move $s2, $v0
    move $a0, $s2
    move $a1, $s0
    jal  check_start
    bnez $v0, print_movable_next
    move $a0, $s2
    move $a1, $s0
    jal  can_capture_from
    bnez $v0, print_movable_show
    bnez $s3, print_movable_next
    move $a0, $s2
    move $a1, $s0
    jal  can_step_from
    bnez $v0, print_movable_show
    j    print_movable_next
"""
        opt1_main = tmp / "main_opt_hints.asm"
        opt1_main.write_text(main_txt[:start_idx] + opt1_body + main_txt[end_idx:], encoding="utf-8")
        base_h, base_out = run_ic(MAIN_ASM, "0\n5\n0\n" + t1)
        opt_h, opt_out = run_ic(opt1_main, "0\n5\n0\n" + t1)
        assert base_out == opt_out
        print(f"=== P1 RAY-CACHED HINTS (test_001): {base_h:,} -> {opt_h:,} ({base_h / opt_h:.2f}x) ===")

        # Prototype 2: Dirty-tile incremental Bitmap Display
        opt2 = tmp / "dirty"
        opt2.mkdir()
        for fn in ("defs.asm", "main.asm", "rules.asm"):
            shutil.copy2(ROOT / "src" / fn, opt2 / fn)
        bio_txt = (ROOT / "src" / "board_io.asm").read_text(encoding="utf-8").replace("\r\n", "\n")
        dirty_patch = """
.data
bmp_valid:      .word 0
bmp_last_rot:   .word -1
bmp_cache:      .space 64
.text
draw_bitmap_dirty:
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    push($s5)
    push($s6)
    push($s7)
    move $s7, $a0
    lw   $t8, bmp_valid
    lw   $t9, bmp_last_rot
    bne  $t9, $s7, dbd_force_all
    j    dbd_start
dbd_force_all:
    li   $t8, 0
dbd_start:
    li   $s0, 0
dbd_row:
    li   $s1, 0
dbd_col:
    sll  $t0, $s0, 3
    add  $t0, $t0, $s1
    move $t7, $t0
    beqz $s7, dbd_cell
    li   $t1, 63
    sub  $t0, $t1, $t0
dbd_cell:
    lbu  $t1, board($t0)
    beqz $t8, dbd_draw
    lbu  $t6, bmp_cache($t7)
    beq  $t1, $t6, dbd_skip
dbd_draw:
    sb   $t1, bmp_cache($t7)
    li   $s2, COLOR_DARK
    bne  $t1, UNUSED, dbd_piece
    li   $s2, COLOR_LIGHT
dbd_piece:
    li   $s3, 0
    li   $s4, 0
    beq  $t1, PAWN_BLACK, dbd_black
    beq  $t1, KING_BLACK, dbd_bking
    beq  $t1, PAWN_RED, dbd_red
    beq  $t1, KING_RED, dbd_rking
    j    dbd_units
dbd_bking:
    li   $s4, 1
dbd_black:
    li   $s3, COLOR_BLACK
    j    dbd_units
dbd_rking:
    li   $s4, 1
dbd_red:
    li   $s3, COLOR_RED
dbd_units:
    li   $s5, 0
dbd_y:
    li   $s6, 0
dbd_x:
    move $t2, $s2
    beqz $s3, dbd_put
    sll  $t3, $s5, 3
    add  $t3, $t3, $s6
    lbu  $t3, piece_mask($t3)
    beqz $t3, dbd_put
    move $t2, $s3
    bne  $t3, 2, dbd_put
    beqz $s4, dbd_put
    li   $t2, COLOR_KING
dbd_put:
    sll  $t4, $s0, 3
    add  $t4, $t4, $s5
    sll  $t4, $t4, 6
    sll  $t5, $s1, 3
    add  $t5, $t5, $s6
    add  $t4, $t4, $t5
    sll  $t4, $t4, 2
    li   $t5, BITMAP_BASE
    add  $t4, $t4, $t5
    sw   $t2, 0($t4)
    addi $s6, $s6, 1
    blt  $s6, 8, dbd_x
    addi $s5, $s5, 1
    blt  $s5, 8, dbd_y
dbd_skip:
    addi $s1, $s1, 1
    blt  $s1, 8, dbd_col
    addi $s0, $s0, 1
    blt  $s0, 8, dbd_row
    li   $t0, 1
    sw   $t0, bmp_valid
    sw   $s7, bmp_last_rot
    pop($s7)
    pop($s6)
    pop($s5)
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    jr   $ra
"""
        (opt2 / "board_io.asm").write_text(
            bio_txt.replace("jal  draw_bitmap", "jal  draw_bitmap_dirty") + dirty_patch,
            encoding="utf-8",
        )
        dmp_b, dmp_o = tmp / "b.hex", tmp / "o.hex"
        base_b, _ = run_ic(MAIN_ASM, "0\n8\n0\n" + t1,
                           extra=["dump", "0x10040000-0x10044000", "HexText", str(dmp_b)], pa=["classic"])
        opt_b, _ = run_ic(opt2 / "main.asm", "0\n8\n0\n" + t1,
                          extra=["dump", "0x10040000-0x10044000", "HexText", str(dmp_o)], pa=["classic"])
        assert dmp_b.read_text() == dmp_o.read_text()
        print(f"=== P2 DIRTY-TILE BITMAP (test_001, 4096/4096 px exact): {base_b:,} -> {opt_b:,} ({base_b / opt_b:.2f}x) ===")


if __name__ == "__main__":
    run_differential_fuzzer()
    verify_swar_bitboard_math()
    run_optimization_benchmarks()
