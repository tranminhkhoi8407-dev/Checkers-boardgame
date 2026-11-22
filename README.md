# Checkers Boardgame in MARS MIPS32 Assembly (v2.0 Hybrid SWAR Engine) -- CO2008

**Ho Chi Minh City University of Technology (HCMUT)** -- Faculty of Computer Science and Engineering  
**Course:** Computer Architecture Lab (`CO2008`) -- Class `CC06`  
**Instructor:** Nguyen Thanh Loc

| Member | Student ID | Primary Responsibility |
| --- | --- | --- |
| **Tran Minh Khoi** | `2550117` | Rules engine (`src/rules.asm`), fixture harness, Tkinter viewer, integration |
| **Nguyen Thanh Hau** | `2550049` | Board state, I/O, Bitmap Display, main loop & menu (`src/defs.asm`, `src/board_io.asm`, `src/main.asm`, `src/main.cpp`), unit/feature tests |
| **Mac Phuc Khang** | `2550082` | Deep code & microarchitectural audit, deployed v2.0 SWAR & Dirty-Tile optimizations, live MARS Perft & differential fuzzing, LaTeX technical report (`report/`) |

---

## v2.0 Microarchitectural & Algorithmic Upgrades (Live in `src/*.asm`)

Building on the complete English Checkers ruleset and 14-item interactive menu, the v2.0 production MIPS32 engine integrates state-of-the-art draughts-engine algorithms and pipeline optimizations directly into `src/*.asm` (48 procedures: 23 leaf, 25 non-leaf; `2,283` basic MIPS32 instructions; strictly bounded `116 B` stack; `0` ABI violations):

1. **Hybrid 64-Byte Mailbox + 32-Bit Chinook SWAR Bitboard Core (`src/rules.asm`, `src/main.asm`):**
   - Pure-leaf `pack_bitboards` packs the 32 dark squares of `board[64]` into three CPU registers (`BP`, `RP`, `K`) using alternating row-end stride (`-1/+1`), zero-stall load-use scheduling, and bit-5/bit-6 ASCII case decoding.
   - **3-Shift Chinook Step Operators** (`swar_up_steps`, `swar_dn_steps`) and **Exact Capture Kernels** (`swar_up_caps`, `swar_dn_caps`) power `has_any_move` (exact for both standard and flying kings via the *Mobility Equivalence Theorem*) and `side_has_capture` (with sparse king-bitmask fallback `OWN & K` for flying kings).
   - **Chinook Direction-Reversal Duality (`print_movable_pieces`, `print_landing_squares`, `print_bitmask`):** Reuses the exact same SWAR capture/step kernels forward for landing squares and reversed over `E` for movable pieces, with native `bgez + sll` MSB bit scanning for Red's player-relative numbering (`33 - s`).
   - **Branchless SWAR Hamming Weight (`count_pieces`, `src/board_io.asm`):** Implements the MIT HAKMEM / *Hacker's Delight* (Sec. 5-1) parallel 32-bit `popcount` in 14 branchless ALU instructions.
2. **Dirty-Tile LICM + 8-Way Unrolled + Zero-Stall Bitmap Display (`draw_bitmap`, `src/board_io.asm`):**
   - Tracks 64 display tiles in `bmp_cache[64]` (`bmp_valid`, `bmp_last_rot`), redrawing only the 2-3 modified tiles per move (with automatic full redraw on startup, game restart, or 180-degree rotation).
   - Hoists tile base pointer calculation once per tile (LICM), accelerates empty/light tiles via an **8-way unrolled solid-tile fast path** (`draw_bitmap_solid_y`), and eliminates the inner-loop load-use pipeline stall by scheduling `addi $t5, $t5, 1` in the delay slot of `lbu $t3, 0($t5)`.

### Live MARS 4.5 Performance Comparison (v1.0 Baseline vs. v2.0 Deployed)

| Benchmark / Workload (Live `Mars45.jar nc ic`) | v1.0 Baseline (`ic`) | v2.0 Deployed (`ic`) | Speedup | Reduction |
| --- | ---: | ---: | ---: | ---: |
| `draw_bitmap` (single dirty move: 2 changed tiles) | 81,263 | **1,908** | **42.59x** | `-97.7%` |
| `draw_bitmap` (cold first full 64x64 frame) | 81,263 | **23,708** | **3.43x** | `-70.8%` |
| `side_has_capture` (single call, start board) | ~4,408 | **525** | **8.40x** | `-88.1%` |
| `test_001` Classic + Bitmap Display (full game) | 2,812,330 | **185,144** | **15.19x** | `-93.4%` (net Bitmap **29.17x**) |
| `test_001` Pretty + Bitmap Display (full game) | 3,014,063 | **338,705** | **8.90x** | `-88.8%` |
| `test_001` Pretty + Move Hints (full game) | 1,512,982 | **292,470** | **5.17x** | `-80.7%` (net Hints **23.79x**) |
| `test_001` Pretty Board (default UI) | 302,523 | **241,591** | **1.25x** | `-20.1%` |
| Classic Fixtures `test_001..005` (5-game mean) | 101,776 | **84,812** | **1.20x** | `-16.7%` (`-12.8%` to `-20.7%`) |

---

## Repository Structure

```text
.
|-- Mars45.jar                              # MARS 4.5 MIPS Assembler & Runtime Simulator
|-- CA_Assignment_261.pdf                   # Official CO2008 assignment specification
|-- main.py                                 # Tkinter GUI replay viewer for fixture games
|-- src/
|   |-- defs.asm                            # Shared constants (.eqv) and stack/I/O macros
|   |-- main.asm                            # Main loop, menu, Chinook SWAR bidirectional hints, history, draw
|   |-- board_io.asm                        # 64B board, SWAR popcount, Dirty-Tile LICM Bitmap, syscall 14 parser
|   |-- rules.asm                           # Rules engine + 32-bit Chinook SWAR bitboard kernels
|   `-- main.cpp                            # Executable C++ reference model (classic core rules)
|-- tests/
|   |-- test_001/ .. test_005/              # Five complete benchmark games (input.txt, expected.txt, outputs)
|   |-- unit/rules_driver.asm               # Standalone MIPS harness for unit tests, Perft, & fuzzing
|   |-- mars_runner.py                      # Subprocess runner for MARS 4.5
|   |-- output_check.py                     # Unified-diff output comparator
|   |-- test_mips.py                        # 5 full-game byte-for-byte MIPS transcript tests
|   |-- test_rules.py                       # 12 isolated unit tests via rules_driver.asm
|   |-- test_features.py                    # 30 end-to-end feature, robustness, and Bitmap memory tests
|   |-- test_advanced_verification.py       # 7 tests: live MARS Perft(1..3), SWAR invariance, Dirty-Tile stress, ABI
|   `-- test_c.py                           # 5 C++ reference cross-checks
`-- report/
    |-- main.tex                            # Full 27-page HCMUT LaTeX report (pdfLaTeX / TeX Live 2026)
    |-- main.pdf                            # Compiled publication-grade PDF report (0 warnings / 0 overfulls)
    |-- CO2008_Checkers_Report_Overleaf.zip # Clean 1-click Overleaf upload archive
    |-- hcmut.png                           # Official HCMUT emblem
    |-- sections/                           # Modular report chapters (01_intro.tex .. 08_conclusion_refs.tex)
    |-- figures/                            # Live MARS Bitmap dumps & 300-DPI v1-vs-v2 benchmark chart
    `-- audit/                              # Reproducible binary decoder, 4,000-query fuzzer & v1-vs-v2 benchmarks
```

---

## Running on MARS 4.5

### Terminal / CLI Mode
Run from the repository root:

```powershell
# Default mode: framed dual-panel board with square numbers, piece counts & rule banner
java -jar Mars45.jar nc src/main.asm

# Classic mode: compact 8x8 specification format for transcript comparison
java -jar Mars45.jar nc src/main.asm pa classic
```

### MARS GUI Mode & Bitmap Display
1. Launch `java -jar Mars45.jar` and open `src/main.asm`.
2. In **Settings**, disable **Assemble all files in directory** (because `src/main.asm` pulls in `defs.asm`, `board_io.asm`, and `rules.asm` via `.include`) and disable **Delayed branching**.
3. Keep all four `.asm` files together inside `src/`.
4. *(Optional -- Graphical Bitmap Display)* Open **Tools -> Bitmap Display** and configure:
   - **Unit Width / Unit Height:** `8`
   - **Display Width / Display Height:** `512`
   - **Base address for display:** `0x10040000 (heap)`
   - Click **Connect to MIPS**, press **F3** (Assemble), then **F5** (Run). Enter `0 -> 8 -> 0` in **Run I/O** to render the live incremental Bitmap board.

---

## Gameplay & Interactive Menu

- **Black moves first.** Enter a starting square (`1`-`32`), then a landing square (`1`-`32`). Square `1` is the leftmost dark square on the top row; square `29` is the bottom-left corner.
- `b` / `r` denote pawns and `B` / `R` denote kings. The framed board uses `.` for empty playable squares; the compact classic board uses `0` for empty dark squares and `_` for unused light squares.
- Enter `0` at **Enter starting square** to open the **14-item Settings & Actions Menu**:
  - `1` Pretty board (frame + square numbers + live SWAR popcount tallies)
  - `2` Rotate board 180 degrees on Red's turn (standard numbering)
  - `3` Red's own square numbering (`33 - s`, automatically rotates Red's view so bottom-left is `29`)
  - `4` Detailed 11-code error explanations
  - `5` Legal move hints (Chinook Bidirectional SWAR movable pieces & landing squares)
  - `6` **Forced first capture** (full English tournament capture rule)
  - `7` **Flying kings** variant (arbitrary-distance diagonal steps & long-range captures)
  - `8` **MARS Bitmap Display** renderer (`0x10040000`, Dirty-Tile incremental updates)
  - `9` Prompt to play again after game over
  - `10` Show move history in standard checkers notation
  - `11` Offer / accept a mutual draw
  - `12` Restart the game immediately
  - `13` Quit
  - `14` Enable all quality-of-life options (`1-5`, `9`) at once
  - `0` Return to the game
- Invalid moves retain the active player's turn. Multi-jump capture chains lock onto the capturing piece and prompt only for the next landing square. Pawns promoted via capture can immediately chain-capture backward in the same turn (Specification Fig. 8).

---

## Testing, Live MARS Perft, Differential Fuzzing & Deep Audit

```powershell
# Replay fixture test_001 directly on MARS 4.5
Get-Content tests/test_001/input.txt | java -jar Mars45.jar nc src/main.asm pa classic

# Run all 54 automated MIPS tests (requires Java + pytest)
python -m pytest -v tests/test_mips.py tests/test_rules.py tests/test_features.py tests/test_advanced_verification.py

# Include the 5 C++ reference cross-checks (requires g++)
python -m pytest -v tests/

# Launch the interactive Tkinter fixture replay viewer
python main.py

# Reproduce the static MIPS32 binary decoder, 4,000-query differential fuzzer,
# 10,000-board SWAR Duality verifier, and live v1.0-vs-v2.0 MARS benchmarks
python report/audit/microarch_audit.py
python report/audit/fuzz_and_optimize.py
```

### Verification Summary (Live MARS 4.5)

| Verification Tier | Coverage & Automated Test Mapping | Result |
| --- | --- | --- |
| Full-Game Classic Fixtures (`test_mips.py`) | `test_001`..`test_005` byte-for-byte match (elimination + blockade trapping) | **5 / 5 PASS** |
| Isolated Rules Unit Suite (`test_rules.py`) | Init, bounds/ownership, promotion, Spec Fig. 8 chain, Fig. 9 trap, forced capture, flying kings | **12 / 12 PASS** |
| End-to-End Features & Robustness (`test_features.py`) | Malformed input/EOF/CRLF, menu, pretty board, rotation/relnum, hints, draw, history, replay, Bitmap | **30 / 30 PASS** |
| Live MARS Perft & v2.0 Stress (`test_advanced_verification.py`) | WCDF `Perft(1..3) = 7 / 49 / 302`, Classic `Perft(1..3) = 7 / 49 / 379`, 120-board SWAR + Mobility Equivalence, Bidirectional SWAR hints, 4,096/4,096 px Dirty-Tile Bitmap stress, static ABI & ASCII hygiene | **7 / 7 PASS** |
| Differential Property-Based Fuzzing (`report/audit/`) | 500 random boards x 8 queries vs. independent Python oracle + 10,000 SWAR Duality/popcount proofs | **4,000 / 4,000 PASS** |

---

## Live Demo Script (Advanced Rules & Assembly Walkthrough)

Start a fresh game with standard numbering (`java -jar Mars45.jar nc src/main.asm`) and enter one integer per line:

| Stage | Input Sequence | Observed Behavior |
| --- | --- | --- |
| Opening setup | `23-19 9-14 27-23 6-9 32-27 2-6 23-18` | Opens the diagonal leading to Red's turn. |
| Chain & Promotion | Red `14x23 23x32`, then Black `22-18` | Red double-jumps, crowns to `R` at `32`; Black places a piece at `18` three diagonal squares away. |
| Enable Rules & QoL | `0 -> 4 -> 5 -> 6 -> 7 -> 0` | Banner displays **Kings Flying \| First capture Required**. Hints list piece `32` and landing square `14`. |
| Forced Capture Check | `32-27` | Rejected with forced-capture error; Red retains turn. |
| Flying Capture & Log | `32x14`, then `0 -> 10` | Red king captures `18` from afar and lands on `14`; history prints the match in standard notation. |

- **Rotated Red View Demo:** Start a new game and toggle option `3`. After Black plays `21-17`, Red sees a 180-degree rotated board with square `29` at bottom-left. Typing `24-20` in Red's view executes canonical `9-13`. Toggle `8` with Bitmap Display connected to show graphical and terminal views side-by-side.
- **Assembly Oral-Defense Walkthrough:** Trace `11x2 2x9 9x18` in `test_001`: `sq_to_rc` maps square indices to `(row, col)` using shifts/masks; `play_turn` passes `($a0, $a1, $a2)` to `validate_move`; `do_move` relocates the piece, clears jumped intermediate squares, and promotes at row `0` *before* `can_capture_from` re-reads the landing square--enabling immediate backward chain jumps in the same turn.
