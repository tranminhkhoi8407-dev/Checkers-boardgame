# Checkers Boardgame in MARS MIPS32 Assembly — CO2008

**Ho Chi Minh City University of Technology (HCMUT)** — Faculty of Computer Science and Engineering  
**Course:** Computer Architecture Lab (`CO2008`) — Class `CC06`  
**Instructor:** Nguyen Thanh Loc

| Member | Student ID | Primary Responsibility |
| --- | --- | --- |
| **Tran Minh Khoi** | `2550117` | Rules engine (`src/rules.asm`), fixture harness, Tkinter viewer, integration |
| **Nguyen Thanh Hau** | `2550049` | Board state, I/O, Bitmap Display, main loop & menu (`src/defs.asm`, `src/board_io.asm`, `src/main.asm`, `src/main.cpp`), unit/feature tests |
| **Mac Phuc Khang** | `2550082` | Deep code & microarchitectural audit, differential fuzzing, optimization benchmarks, LaTeX technical report (`report/`) |

---

## Repository Structure

```text
.
├── Mars45.jar                          # MARS 4.5 MIPS Assembler & Runtime Simulator
├── CA_Assignment_261.pdf               # Official CO2008 assignment specification
├── main.py                             # Tkinter GUI replay viewer for fixture games
├── src/
│   ├── defs.asm                        # Shared constants (.eqv) and stack/I/O macros
│   ├── main.asm                        # Main game loop, turn controller, menu, hints, history, draw
│   ├── board_io.asm                    # 64B board, bitwise transforms, text/Bitmap renderers, syscall 14 parser
│   ├── rules.asm                       # Move validation, captures, instant promotion, forced capture, flying kings
│   └── main.cpp                        # Executable C++ reference model (classic core rules)
├── tests/
│   ├── test_001/ .. test_005/          # Five complete benchmark games (input.txt, expected.txt, outputs)
│   ├── unit/rules_driver.asm           # Standalone MIPS harness for isolated unit tests & fuzzing
│   ├── mars_runner.py                  # Subprocess runner for MARS 4.5
│   ├── output_check.py                 # Unified-diff output comparator
│   ├── test_mips.py                    # 5 full-game byte-for-byte MIPS transcript tests
│   ├── test_rules.py                   # 12 isolated unit tests via rules_driver.asm
│   ├── test_features.py                # 30 end-to-end feature, robustness, and Bitmap memory tests
│   └── test_c.py                       # 5 C++ reference cross-checks
└── report/
    ├── main.tex                        # Full 25-page HCMUT LaTeX report (pdfLaTeX / TeX Live 2026)
    ├── main.pdf                        # Compiled publication-grade PDF report
    ├── CO2008_Checkers_Report_Overleaf.zip  # Clean 1-click Overleaf upload archive
    ├── hcmut.png                       # Official HCMUT emblem
    ├── sections/                       # Modular report chapters (01_intro.tex .. 08_conclusion_refs.tex)
    ├── figures/                        # Live MARS Bitmap dumps & 300-DPI microarchitecture benchmark chart
    └── audit/                          # Reproducible binary decoder, 4,000-query fuzzer & optimization benchmarks
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
4. *(Optional — Graphical Bitmap Display)* Open **Tools → Bitmap Display** and configure:
   - **Unit Width / Unit Height:** `8`
   - **Display Width / Display Height:** `512`
   - **Base address for display:** `0x10040000 (heap)`
   - Click **Connect to MIPS**, press **F3** (Assemble), then **F5** (Run). Enter `0 → 8 → 0` in **Run I/O** to render the live graphical board (cream/slate tiles, navy/crimson pieces, and gold pixel-art crowns for kings).

---

## Gameplay & Interactive Menu

- **Black moves first.** Enter a starting square (`1`–`32`), then a landing square (`1`–`32`). Square `1` is the leftmost dark square on the top row; square `29` is the bottom-left corner.
- `b` / `r` denote pawns and `B` / `R` denote kings. The framed board uses `.` for empty playable squares; the compact classic board uses `0` for empty dark squares and `_` for unused light squares.
- Enter `0` at **Enter starting square** to open the **14-item Settings & Actions Menu**:
  - `1` Pretty board (frame + square numbers + live counts)
  - `2` Rotate board $180^\circ$ on Red's turn (standard numbering)
  - `3` Red's own square numbering (`33 - s`, automatically rotates Red's view so bottom-left is `29`)
  - `4` Detailed 11-code error explanations
  - `5` Legal move hints (movable pieces & landing squares)
  - `6` **Forced first capture** (full English tournament capture rule)
  - `7` **Flying kings** variant (arbitrary-distance diagonal steps & long-range captures)
  - `8` **MARS Bitmap Display** renderer (`0x10040000`)
  - `9` Prompt to play again after game over
  - `10` Show move history in standard checkers notation
  - `11` Offer / accept a mutual draw
  - `12` Restart the game immediately
  - `13` Quit
  - `14` Enable all quality-of-life options (`1–5`, `9`) at once
  - `0` Return to the game
- Invalid moves retain the active player's turn. Multi-jump capture chains lock onto the capturing piece and prompt only for the next landing square. Pawns promoted via capture can immediately chain-capture backward in the same turn (Specification Fig. 8).

---

## Testing, Differential Fuzzing & Deep Audit

```powershell
# Replay fixture test_001 directly on MARS 4.5
Get-Content tests/test_001/input.txt | java -jar Mars45.jar nc src/main.asm pa classic

# Run all 47 automated MIPS tests (requires Java + pytest)
python -m pytest -v tests/test_mips.py tests/test_rules.py tests/test_features.py

# Include the 5 C++ reference cross-checks (requires g++)
python -m pytest -v tests/

# Launch the interactive Tkinter fixture replay viewer
python main.py

# Reproduce the microarchitectural binary audit, 4,000-query differential fuzzer,
# and 3 live MIPS optimization prototypes (Ray-Cached Hints, Dirty-Tile Bitmap, 32-bit SWAR Bitboard)
python report/audit/microarch_audit.py
python report/audit/fuzz_and_optimize.py
```

### Verification Summary (Live MARS 4.5)

| Deliverable / Verification Tier | Coverage & Automated Test Mapping | Result |
| --- | --- | --- |
| 12-vs-12 init & Black moves first | `test_initial_board_and_black_moves_first`, `test_initial_board_has_12_pieces_each` | **PASS** |
| Malformed input, CRLF & EOF safety | `test_bad_input_does_not_crash`, `test_end_of_input_exits_cleanly` (3 cases), `test_crlf_and_last_line_without_newline` | **PASS** |
| Invalid move retains turn | `test_invalid_move_does_not_lose_turn`, `test_001` (5 invalid attempts) | **PASS** |
| Turn alternation & chain locking | `test_turns_alternate_after_each_valid_move`, `test_promotion_chain_keeps_turn_and_locks_piece` (`11x2 2x9 9x18`) | **PASS** |
| Win detection (elimination & blockade) | `test_mips_games` (`test_001`/`002`/`005` elimination; `test_003`/`004` trapped blockade), `test_blocked_side_has_no_moves` (Fig. 9) | **PASS** |
| Promotion + immediate backward chain | `test_promotion_by_capture_then_chain_backward` (Fig. 8: `15x24 24x31 31x22 22x13`) | **PASS** |
| Display / input numbering consistency | `test_numbered_board_agrees_with_red_input`, `test_pretty_chain_identifies_the_piece_in_red_numbering` | **PASS** |
| Hints, Forced Capture & Flying Kings | `test_forced_capture_rule`, `test_flying_kings`, `test_flying_king_capture_is_required_and_hinted` | **PASS** |
| Pretty UI, Bitmap Display & Replay | `test_default_board_explains_controls_and_current_rules`, `test_bitmap_display_memory`, `test_pretty_board_reports_elimination_and_restarts_after_win` | **PASS** |
| Differential Property-Based Fuzzing | `report/audit/fuzz_and_optimize.py` — 500 random boards × 8 queries vs. independent Python oracle | **4,000 / 4,000 PASS** |

---

## Live Demo Script (Advanced Rules & Assembly Walkthrough)

Start a fresh game with standard numbering (`java -jar Mars45.jar nc src/main.asm`) and enter one integer per line:

| Stage | Input Sequence | Observed Behavior |
| --- | --- | --- |
| Opening setup | `23-19 9-14 27-23 6-9 32-27 2-6 23-18` | Opens the diagonal leading to Red's turn. |
| Chain & Promotion | Red `14x23 23x32`, then Black `22-18` | Red double-jumps, crowns to `R` at `32`; Black places a piece at `18` three diagonal squares away. |
| Enable Rules & QoL | `0 → 4 → 5 → 6 → 7 → 0` | Banner displays **Kings Flying \| First capture Required**. Hints list piece `32` and landing square `14`. |
| Forced Capture Check | `32-27` | Rejected with forced-capture error; Red retains turn. |
| Flying Capture & Log | `32x14`, then `0 → 10` | Red king captures `18` from afar and lands on `14`; history prints the match in standard notation. |

- **Rotated Red View Demo:** Start a new game and toggle option `3`. After Black plays `21-17`, Red sees a $180^\circ$-rotated board with square `29` at bottom-left. Typing `24-20` in Red's view executes canonical `9-13`. Toggle `8` with Bitmap Display connected to show graphical and terminal views side-by-side.
- **Assembly Oral-Defense Walkthrough:** Trace `11x2 2x9 9x18` in `test_001`: `sq_to_rc` maps square indices to `(row, col)` using shifts/masks; `play_turn` passes `($a0, $a1, $a2)` to `validate_move`; `do_move` relocates the piece, clears jumped intermediate squares, and promotes at row `0` *before* `can_capture_from` re-reads the landing square—enabling immediate backward chain jumps in the same turn.
