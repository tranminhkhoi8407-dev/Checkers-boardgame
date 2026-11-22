"""Differential property-based fuzzer (4,000 queries), SWAR Duality verifier,
and live MARS 4.5 v2.0 production benchmark suite.

Verifies the upgraded v2.0 MIPS32 engine (src/rules.asm, src/board_io.asm,
src/main.asm) against an independent Python oracle across 500 randomized boards
(English, Forced Capture, Flying Kings), verifies 10,000 SWAR bitboard /
Chinook Duality / popcount positions, and benchmarks live v2.0 instruction
counts against the recorded v1.0 pre-optimization baseline.
"""
import pathlib
import random
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
MARS = ROOT / "Mars45.jar"
DRIVER_ASM = ROOT / "tests" / "unit" / "rules_driver.asm"
MAIN_ASM = ROOT / "src" / "main.asm"
JAVA = shutil.which("java") or "java"

# Recorded v1.0 baseline MARS 4.5 instruction counts (commit 5605647, prior to SWAR & Dirty-Tile upgrades)
V1_BASELINE_IC = {
    "test_001_classic": 106306,
    "test_002_classic": 98424,
    "test_003_classic": 106734,
    "test_004_classic": 103767,
    "test_005_classic": 93648,
    "test_001_pretty": 302523,
    "test_001_pretty_hints": 1512982,
    "test_001_classic_bitmap": 2812330,
    "test_001_pretty_bitmap": 3014063,
}


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
    print(f"=== DIFFERENTIAL FUZZER (v2.0 production): {n_boards} boards, {len(expected)} queries ===")
    print(f"Exact matches: {len(actual) - mismatches}/{len(expected)} | Mismatches: {mismatches}")
    assert len(actual) == len(expected) and mismatches == 0


def verify_swar_bitboard_math():
    def up_steps(x): return ((x >> 4) | ((x & 0xE0E0E0E0) >> 5) | ((x & 0x07070700) >> 3)) & 0xFFFFFFFF
    def dn_steps(x): return (((x << 4) | ((x & 0x00E0E0E0) << 3) | ((x & 0x07070707) << 5)) & 0xFFFFFFFF)
    def up_caps(src, opp, dst):
        nw1 = (((src >> 4) & opp & 0x00E0E0E0) >> 5)
        nw2 = ((((src & 0xE0E0E0E0) >> 5) & opp) >> 4)
        ne1 = (((src >> 4) & opp & 0x07070700) >> 3)
        ne2 = ((((src & 0x07070700) >> 3) & opp) >> 4)
        return (nw1 | nw2 | ne1 | ne2) & dst
    def dn_caps(src, opp, dst):
        sw1 = ((((src << 4) & 0xFFFFFFFF) & opp & 0x00E0E0E0) << 3) & 0xFFFFFFFF
        sw2 = (((((src & 0x00E0E0E0) << 3) & 0xFFFFFFFF) & opp) << 4) & 0xFFFFFFFF
        se1 = ((((src << 4) & 0xFFFFFFFF) & opp & 0x07070707) << 5) & 0xFFFFFFFF
        se2 = (((((src & 0x07070707) << 5) & 0xFFFFFFFF) & opp) << 4) & 0xFFFFFFFF
        return (sw1 | sw2 | se1 | se2) & dst
    def popcount(x):
        x = (x - ((x >> 1) & 0x55555555)) & 0xFFFFFFFF
        x = ((x & 0x33333333) + ((x >> 2) & 0x33333333)) & 0xFFFFFFFF
        x = ((x + (x >> 4)) & 0x0F0F0F0F) & 0xFFFFFFFF
        return (((x * 0x01010101) & 0xFFFFFFFF) >> 24)

    rng = random.Random(42)
    for _ in range(10000):
        bp = rng.getrandbits(32) & rng.getrandbits(32)
        rp = (rng.getrandbits(32) & rng.getrandbits(32)) & (~bp & 0xFFFFFFFF)
        k = rng.getrandbits(32) & (bp | rp)
        e = (~(bp | rp)) & 0xFFFFFFFF
        bk = bp & k
        assert popcount(bp) == bin(bp).count("1") and popcount(rp) == bin(rp).count("1")
        swar_cap = 1 if (up_caps(bp, rp, e) | dn_caps(bk, rp, e)) else 0
        swar_mov = 1 if (((up_steps(bp) | dn_steps(bk)) & e) or swar_cap) else 0
        # Verify Chinook Duality for Black capture source pieces
        dual_cap_src = dn_caps(e, rp, bp) | up_caps(e, rp, bk)
        assert bool(dual_cap_src) == bool(swar_cap)
        board = [["_" if (r + c) % 2 == 0 else "0" for c in range(8)] for r in range(8)]
        for b in range(32):
            r, c = sq_rc(b + 1)
            if (bp >> b) & 1:
                board[r][c] = "B" if ((k >> b) & 1) else "b"
            elif (rp >> b) & 1:
                board[r][c] = "R" if ((k >> b) & 1) else "r"
        assert swar_cap == oracle_side_cap(board, 0, False)
        assert swar_mov == oracle_has_move(board, 0, False) == oracle_has_move(board, 0, True)
    print("=== SWAR BITBOARD + DUALITY + POPCOUNT + MOBILITY EQUIVALENCE: 10,000 / 10,000 PASS ===")


def run_production_benchmarks():
    print("=== LIVE MARS 4.5 BENCHMARKS: v1.0 BASELINE vs. v2.0 PRODUCTION ===")
    t1 = (ROOT / "tests" / "test_001" / "input.txt").read_text(encoding="utf-8")
    cases = [
        ("test_001_classic", t1, ["classic"]),
        ("test_002_classic", (ROOT / "tests" / "test_002" / "input.txt").read_text(encoding="utf-8"), ["classic"]),
        ("test_003_classic", (ROOT / "tests" / "test_003" / "input.txt").read_text(encoding="utf-8"), ["classic"]),
        ("test_004_classic", (ROOT / "tests" / "test_004" / "input.txt").read_text(encoding="utf-8"), ["classic"]),
        ("test_005_classic", (ROOT / "tests" / "test_005" / "input.txt").read_text(encoding="utf-8"), ["classic"]),
        ("test_001_pretty", t1, []),
        ("test_001_pretty_hints", "0\n5\n0\n" + t1, []),
        ("test_001_classic_bitmap", "0\n8\n0\n" + t1, ["classic"]),
        ("test_001_pretty_bitmap", "0\n8\n0\n" + t1, []),
    ]
    for name, stdin_text, pa in cases:
        v2_ic, _ = run_ic(MAIN_ASM, stdin_text, pa=pa)
        v1_ic = V1_BASELINE_IC[name]
        print(f"  {name:24s}: {v1_ic:10,} -> {v2_ic:10,}  ({v1_ic / v2_ic:5.2f}x, {(v2_ic - v1_ic) / v1_ic * 100:+6.1f}%)")


if __name__ == "__main__":
    run_differential_fuzzer()
    verify_swar_bitboard_math()
    run_production_benchmarks()
