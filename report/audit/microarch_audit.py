"""Static MIPS32 binary decoder, 5-stage pipeline hazard audit, and SWAR bitboard mask verifier.

Runs directly against Mars45.jar in the repository root and requires Java on PATH.
"""
import collections
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
MARS = ROOT / "Mars45.jar"
MAIN_ASM = ROOT / "src" / "main.asm"
JAVA = shutil.which("java") or "java"

LOAD_OPS = {0x20, 0x21, 0x23, 0x24, 0x25}   # lb, lh, lw, lbu, lhu
STORE_OPS = {0x28, 0x29, 0x2B}              # sb, sh, sw
BRANCH_OPS = {0x01, 0x04, 0x05, 0x06, 0x07} # regimm, beq, bne, blez, bgtz
JUMP_OPS = {0x02, 0x03}                     # j, jal
IMM_ALU_OPS = {0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F}


def decode_text_segment():
    with tempfile.TemporaryDirectory() as td:
        hex_path = pathlib.Path(td) / "text.hex"
        res = subprocess.run(
            [JAVA, "-jar", str(MARS), "nc", "dump", ".text", "HexText", str(hex_path), str(MAIN_ASM)],
            input=b"0\n13\n",
            capture_output=True,
            timeout=30,
        )
        assert res.returncode == 0, res.stderr.decode(errors="replace")
        words = [int(w, 16) for w in hex_path.read_text().split()]

    cats = collections.Counter()
    decoded = []
    for w in words:
        op = (w >> 26) & 0x3F
        rs = (w >> 21) & 0x1F
        rt = (w >> 16) & 0x1F
        rd = (w >> 11) & 0x1F
        fn = w & 0x3F
        info = {"is_load": False, "dst": 0, "srcs": set()}

        if w == 0:
            cats["NOP"] += 1
        elif op == 0x00:
            if fn == 0x0C:
                cats["Syscall"] += 1
                info["srcs"] = {2, 4, 5, 6}
            elif fn in (0x08, 0x09):
                cats["Jump / Call"] += 1
                info["srcs"] = {rs}
            elif fn in (0x00, 0x02, 0x03):
                cats["Shift / Bitwise"] += 1
                info["dst"] = rd
                info["srcs"] = {rt}
            elif fn in (0x04, 0x06, 0x07, 0x24, 0x25, 0x26, 0x27):
                cats["Shift / Bitwise"] += 1
                info["dst"] = rd
                info["srcs"] = {rs, rt}
            else:
                cats["ALU (R-type)"] += 1
                info["dst"] = rd
                info["srcs"] = {rs, rt}
        elif op == 0x1C and fn == 0x02:
            cats["ALU (R-type)"] += 1
            info["dst"] = rd
            info["srcs"] = {rs, rt}
        elif op in LOAD_OPS:
            cats["Load"] += 1
            info["is_load"] = True
            info["dst"] = rt
            info["srcs"] = {rs}
        elif op in STORE_OPS:
            cats["Store"] += 1
            info["srcs"] = {rs, rt}
        elif op in BRANCH_OPS:
            cats["Branch"] += 1
            info["srcs"] = {rs} if op in (1, 6, 7) else {rs, rt}
        elif op in JUMP_OPS:
            cats["Jump / Call"] += 1
        elif op in IMM_ALU_OPS:
            cats["Shift / Bitwise" if op in (0x0C, 0x0D, 0x0E) else "ALU (I-type)"] += 1
            info["dst"] = rt
            info["srcs"] = set() if op == 0x0F else {rs}
        else:
            cats["Other"] += 1
        decoded.append(info)

    print(f"=== STATIC MIPS32 INSTRUCTION MIX ({len(words)} machine words) ===")
    for k, v in cats.most_common():
        print(f"  {k:20s}: {v:4d} ({100.0 * v / len(words):5.2f}%)")

    load_use = sum(
        1 for i in range(len(decoded) - 1)
        if decoded[i]["is_load"] and decoded[i]["dst"] != 0 and decoded[i]["dst"] in decoded[i + 1]["srcs"]
    )
    ex_ex = sum(
        1 for i in range(len(decoded) - 1)
        if not decoded[i]["is_load"] and decoded[i]["dst"] != 0 and decoded[i]["dst"] in decoded[i + 1]["srcs"]
    )
    print(f"\nStatic load-use hazard pairs: {load_use} / {cats['Load']} loads ({100.0 * load_use / cats['Load']:.1f}%)")
    print(f"Static EX->EX forwarding pairs: {ex_ex} ({100.0 * ex_ex / len(words):.1f}% of instructions)")


def derive_swar_masks():
    print("\n=== EXACT 32-BIT CHINOOK SWAR BITBOARD MASKS (bit b = sq - 1) ===")
    def rc_of_bit(b):
        r = b // 4
        c = 2 * (b % 4) + (1 if r % 2 == 0 else 0)
        return r, c
    bit_of_rc = {rc_of_bit(b): b for b in range(32)}
    for name, dr, dc in [("NW (Up-Left)", -1, -1), ("NE (Up-Right)", -1, 1),
                         ("SW (Down-Left)", 1, -1), ("SE (Down-Right)", 1, 1)]:
        deltas = collections.defaultdict(int)
        for b in range(32):
            r, c = rc_of_bit(b)
            if (r + dr, c + dc) in bit_of_rc:
                nb = bit_of_rc[(r + dr, c + dc)]
                deltas[nb - b] |= (1 << b)
        print(f"  {name:16s}: " + ", ".join(f"shift {d:+d} with mask 0x{m:08X}" for d, m in sorted(deltas.items())))


if __name__ == "__main__":
    decode_text_segment()
    derive_swar_masks()
