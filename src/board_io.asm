###############################################################################
# board_io.asm - BOARD STATE, RENDERING, AND INPUT (Owner: Nguyen Thanh Hau)
#
#   - Board storage and initialization (12 pieces per side).
#   - Conversions between square numbers 1..32, (row, col), and array index.
#   - Board rendering: classic format, framed board with square numbers,
#     180-degree player rotation, and MARS Bitmap Display rendering.
#   - Fault-tolerant input parsing: letters, blank lines, overflow, and EOF
#     never crash the simulator.
#   - Concise and detailed error message reporting.
#
# Included by main.asm; follows the same MIPS calling conventions as rules.asm.
###############################################################################

.data
# 8x8 board at board[r*8 + c]. '_' = unused light square, '0' = empty dark square.
board:          .space 64
start_board:    .ascii "_r_r_r_r"
                .ascii "r_r_r_r_"
                .ascii "_r_r_r_r"
                .ascii "0_0_0_0_"
                .ascii "_0_0_0_0"
                .ascii "b_b_b_b_"
                .ascii "_b_b_b_b"
                .ascii "b_b_b_b_"

# 8x8 pixel sprite mask for Bitmap Display tiles.
# 0 = tile background, 1 = piece body, 2 = crown (painted gold for kings only).
piece_mask:     .byte 0,0,0,0,0,0,0,0
                .byte 0,0,1,1,1,1,0,0
                .byte 0,1,2,1,1,2,1,0
                .byte 0,1,2,2,2,2,1,0
                .byte 0,1,1,2,2,1,1,0
                .byte 0,1,1,1,1,1,1,0
                .byte 0,0,1,1,1,1,0,0
                .byte 0,0,0,0,0,0,0,0

input_chunk:    .space INPUT_CHUNK_SIZE
input_line:     .space INPUT_SIZE
input_next:     .word 0
input_end:      .word 0

# Dirty-tile cache for incremental MARS Bitmap Display updates
bmp_valid:      .word 0
bmp_last_rot:   .word -1
bmp_cache:      .space 64

str_black:      .asciiz "Black"
str_red:        .asciiz "Red"
str_invalid:    .asciiz "Not a valid move! Try again.\n"
str_invalid_pre:.asciiz "Not a valid move! "
str_try_again:  .asciiz " Try again.\n"

str_pretty_title: .asciiz "\n  CHECKERS\n"
str_pretty_kings: .asciiz "  Kings  "
str_pretty_short: .asciiz "Standard"
str_pretty_flying:.asciiz "Flying"
str_pretty_cap:   .asciiz "    |    First capture  "
str_pretty_optional:.asciiz "Optional\n"
str_pretty_required:.asciiz "Required\n"
str_pretty_head1: .asciiz "  Black (b, B = king): "
str_pretty_head2: .asciiz "    Red (r, R = king): "
str_pretty_rot:   .asciiz "    [Red's view]"
str_pretty_cols:  .asciiz "  POSITION                             PLAYABLE SQUARES\n"
str_pretty_line:  .asciiz "  +---+---+---+---+---+---+---+---+    +---+---+---+---+---+---+---+---+\n"
str_pretty_gap:   .asciiz "    |"
str_pretty_foot:  .asciiz "  .  Empty square     |     0  Settings (at the starting-square prompt)\n"

# Detailed diagnostic messages indexed by ERR_* codes (when opt_detail = 1)
err_table:      .word err_txt_none, err_txt_range, err_txt_empty, err_txt_not_yours
                .word err_txt_occupied, err_txt_diagonal, err_txt_backward
                .word err_txt_too_far, err_txt_no_enemy, err_txt_must_capture
                .word err_txt_chain, err_txt_blocked
err_txt_none:        .asciiz ""
err_txt_range:       .asciiz "Please type a square number from 1 to 32."
err_txt_empty:       .asciiz "There is no piece on that starting square."
err_txt_not_yours:   .asciiz "That piece belongs to your opponent."
err_txt_occupied:    .asciiz "The landing square is not empty."
err_txt_diagonal:    .asciiz "Pieces can only move diagonally."
err_txt_backward:    .asciiz "Pawns can only move forward; only kings move backward."
err_txt_too_far:     .asciiz "Move 1 square, or jump 2 squares over an enemy piece."
err_txt_no_enemy:    .asciiz "There is no enemy piece to jump over."
err_txt_must_capture:.asciiz "A capture is available, so you must capture (forced capture rule)."
err_txt_chain:       .asciiz "You must keep capturing with the same piece."
err_txt_blocked:     .asciiz "The path is blocked (you may jump over exactly one enemy piece)."

.text

# -----------------------------------------------------------------------------
# init_board() - copy initial 12-vs-12 position from start_board into board
# -----------------------------------------------------------------------------
init_board:
    li   $t0, 0
init_board_loop:
    lbu  $t1, start_board($t0)
    sb   $t1, board($t0)
    addi $t0, $t0, 1
    blt  $t0, 64, init_board_loop
    sw   $zero, bmp_valid       # invalidate Bitmap Display dirty-tile cache
    jr   $ra

# -----------------------------------------------------------------------------
# sq_to_rc(a0 = square 1..32) -> v0 = row, v1 = col
#   row = (s-1)/4 ; col = 2*((s-1)%4) + (row even ? 1 : 0)
# -----------------------------------------------------------------------------
sq_to_rc:
    addi $t0, $a0, -1
    srl  $v0, $t0, 2            # row = (s-1) / 4
    andi $t1, $t0, 3
    sll  $v1, $t1, 1            # 2 * ((s-1) % 4)
    andi $t2, $v0, 1
    xori $t2, $t2, 1            # even rows shift dark squares right by 1 col
    add  $v1, $v1, $t2
    jr   $ra

# -----------------------------------------------------------------------------
# idx_to_sq(a0 = dark-square index 0..63) -> v0 = square number 1..32
#   s = row*4 + col/2 + 1
# -----------------------------------------------------------------------------
idx_to_sq:
    srl  $t0, $a0, 3            # row
    andi $t1, $a0, 7            # col
    sll  $v0, $t0, 2
    srl  $t1, $t1, 1
    add  $v0, $v0, $t1
    addi $v0, $v0, 1
    jr   $ra

# -----------------------------------------------------------------------------
# get_cell(a0 = row, a1 = col) -> v0 = cell char, or 0 if out of bounds
# -----------------------------------------------------------------------------
get_cell:
    li   $v0, 0
    bltz $a0, get_cell_ret
    bge  $a0, 8, get_cell_ret
    bltz $a1, get_cell_ret
    bge  $a1, 8, get_cell_ret
    sll  $t0, $a0, 3
    add  $t0, $t0, $a1
    lbu  $v0, board($t0)
get_cell_ret:
    jr   $ra

# -----------------------------------------------------------------------------
# square_piece(a0 = square 1..32) -> v0 = cell char on that square
# -----------------------------------------------------------------------------
square_piece:
    push($ra)
    jal  sq_to_rc
    sll  $t0, $v0, 3
    add  $t0, $t0, $v1
    lbu  $v0, board($t0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# count_pieces(a0 = side) -> v0 = remaining piece count (pawns + kings) for side
# Packs board[64] into 32-bit bitboards and computes Hamming weight using
# branchless SWAR parallel popcount (Hacker's Delight, Sec. 5-1).
# -----------------------------------------------------------------------------
count_pieces:
    push($ra)
    push($s0)
    move $s0, $a0               # preserve side across pack_bitboards
    jal  pack_bitboards         # v0 = BP, v1 = RP
    beqz $s0, count_pieces_pop
    move $v0, $v1               # select Red bitboard
count_pieces_pop:
    srl  $t0, $v0, 1
    li   $t1, 0x55555555
    and  $t0, $t0, $t1
    subu $v0, $v0, $t0          # 2-bit partial sums
    li   $t1, 0x33333333
    and  $t0, $v0, $t1
    srl  $v0, $v0, 2
    and  $v0, $v0, $t1
    addu $v0, $v0, $t0          # 4-bit partial sums
    srl  $t0, $v0, 4
    addu $v0, $v0, $t0
    li   $t1, 0x0F0F0F0F
    and  $v0, $v0, $t1          # 8-bit partial sums (each <= 8)
    li   $t1, 0x01010101
    mul  $v0, $v0, $t1          # horizontal sum into MSB
    srl  $v0, $v0, 24
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# view_index(a0 = display row, a1 = display col, a2 = rotated?) -> v0 = index
# 180-degree rotation maps (r, c) to (7-r, 7-c), i.e., flat index 63 - i.
# -----------------------------------------------------------------------------
view_index:
    sll  $v0, $a0, 3
    add  $v0, $v0, $a1
    beqz $a2, view_index_ret
    li   $t0, 63
    sub  $v0, $t0, $v0
view_index_ret:
    jr   $ra

# -----------------------------------------------------------------------------
# board_rotated(a0 = viewing side) -> v0 = 1 if board should rotate for side
# Enabling Red's own numbering also activates rotation so square 29 is bottom-left.
# -----------------------------------------------------------------------------
board_rotated:
    lw   $v0, opt_rotate
    lw   $t0, opt_relnum
    or   $v0, $v0, $t0
    and  $v0, $v0, $a0          # SIDE_RED = 1
    jr   $ra

# -----------------------------------------------------------------------------
# view_square(a0 = square, a1 = side) -> v0 = square in side's numbering
# Involutive transform: when Red uses player-relative numbering (bottom-left
# is square 29), canonical = 33 - relative and vice versa.
# -----------------------------------------------------------------------------
view_square:
    move $v0, $a0
    blt  $a0, 1, view_square_ret
    bgt  $a0, 32, view_square_ret
    beqz $a1, view_square_ret
    lw   $t0, opt_relnum
    beqz $t0, view_square_ret
    li   $t0, 33
    sub  $v0, $t0, $a0
view_square_ret:
    jr   $ra

# -----------------------------------------------------------------------------
# read_input_line() -> v0 = line length, INPUT_INVALID, or INPUT_END.
# Reads stdin via syscall 14 (fd=0) to detect EOF reliably on MARS CLI while
# also supporting Run I/O on MARS GUI. Retains unread bytes across calls and
# drains overlong lines up to '\n' so subsequent reads stay synchronized.
# -----------------------------------------------------------------------------
read_input_line:
    li   $t0, 0                 # line length (saturates at INPUT_SIZE + 1)
read_line_next:
    lw   $t1, input_next
    lw   $t2, input_end
    blt  $t1, $t2, read_line_byte
    li   $a0, 0                 # stdin file descriptor
    la   $a1, input_chunk
    li   $a2, INPUT_CHUNK_SIZE
    li   $v0, 14
    syscall
    blez $v0, read_line_end
    sw   $v0, input_end
    li   $t1, 0
read_line_byte:
    lbu  $t2, input_chunk($t1)
    addi $t1, $t1, 1
    sw   $t1, input_next
    beq  $t2, '\n', read_line_finish
    bgt  $t0, INPUT_SIZE, read_line_next
    beq  $t0, INPUT_SIZE, read_line_count
    sb   $t2, input_line($t0)
read_line_count:
    addi $t0, $t0, 1
    j    read_line_next
read_line_end:
    beqz $t0, read_line_eof       # allow final line without trailing '\n'
read_line_finish:
    li   $v0, INPUT_INVALID
    bgt  $t0, INPUT_SIZE, read_line_ret
    beqz $t0, read_line_terminate
    addi $t1, $t0, -1
    lbu  $t2, input_line($t1)
    bne  $t2, '\r', read_line_terminate
    move $t0, $t1               # strip trailing CR for CRLF compatibility
read_line_terminate:
    bge  $t0, INPUT_SIZE, read_line_ret
    sb   $zero, input_line($t0)
    move $v0, $t0
read_line_ret:
    jr   $ra
read_line_eof:
    li   $v0, INPUT_END
    jr   $ra

# -----------------------------------------------------------------------------
# read_number() -> v0 = non-negative integer, INPUT_INVALID, or INPUT_END.
#
# Accepts leading/trailing spaces or tabs. Values > 9999 clamp safely to 9999.
# -----------------------------------------------------------------------------
read_number:
    push($ra)
    jal  read_input_line
    bltz $v0, read_number_ret
    la   $t0, input_line
    addu $t3, $t0, $v0          # true end of line (rejects embedded NUL bytes)
read_number_lead:               # skip leading whitespace
    lbu  $t1, 0($t0)
    beq  $t1, ' ', read_number_lead_next
    bne  $t1, '\t', read_number_digits_init
read_number_lead_next:
    addi $t0, $t0, 1
    j    read_number_lead
read_number_digits_init:
    li   $v0, 0                 # parsed value
    li   $t2, 0                 # digit count
read_number_digits:
    lbu  $t1, 0($t0)
    blt  $t1, '0', read_number_tail
    bgt  $t1, '9', read_number_tail
    addi $t2, $t2, 1
    addi $t0, $t0, 1
    bge  $v0, 1000, read_number_cap
    mul  $v0, $v0, 10
    addi $t1, $t1, -48
    add  $v0, $v0, $t1
    j    read_number_digits
read_number_cap:
    li   $v0, 9999
    j    read_number_digits
read_number_tail:               # only whitespace allowed after digits
    beq  $t1, ' ', read_number_tail_next
    beq  $t1, '\t', read_number_tail_next
    j    read_number_end
read_number_tail_next:
    addi $t0, $t0, 1
    lbu  $t1, 0($t0)
    j    read_number_tail
read_number_end:
    beqz $t2, read_number_bad
    beq  $t0, $t3, read_number_ret
read_number_bad:
    li   $v0, INPUT_INVALID
read_number_ret:
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# read_square(a0 = active side) -> v0 = canonical square (1..32), 0 (menu),
# or INPUT_INVALID / INPUT_END. Automatically translates player-relative input.
# -----------------------------------------------------------------------------
read_square:
    push($ra)
    push($s0)
    move $s0, $a0
    jal  read_number
    move $a0, $v0
    move $a1, $s0
    jal  view_square
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# print_side(a0 = side) - print "Black" or "Red"
# -----------------------------------------------------------------------------
print_side:
    la   $t0, str_black
    beqz $a0, print_side_go
    la   $t0, str_red
print_side_go:
    move $a0, $t0
    li   $v0, 4
    syscall
    jr   $ra

# -----------------------------------------------------------------------------
# print_error(a0 = error code) - report an invalid move
# Prints standard message by default; prints detailed reason when opt_detail=1.
# -----------------------------------------------------------------------------
print_error:
    lw   $t0, opt_detail
    bnez $t0, print_error_detail
    print_str(str_invalid)
    jr   $ra
print_error_detail:
    move $t1, $a0
    print_str(str_invalid_pre)
    sll  $t1, $t1, 2
    lw   $a0, err_table($t1)
    li   $v0, 4
    syscall
    print_str(str_try_again)
    jr   $ra

# -----------------------------------------------------------------------------
# print_board(a0 = upcoming side) - render board according to active options
# -----------------------------------------------------------------------------
print_board:
    push($ra)
    push($s0)
    push($s1)
    move $s0, $a0
    jal  board_rotated
    move $s1, $v0               # s1 = rotated flag
    lw   $t0, opt_pretty
    bnez $t0, print_board_fancy
    move $a0, $s1
    jal  print_board_plain
    j    print_board_bitmap
print_board_fancy:
    jal  print_board_rules
    move $a0, $s0
    move $a1, $s1
    jal  print_board_pretty
print_board_bitmap:
    lw   $t0, opt_bitmap
    beqz $t0, print_board_ret
    move $a0, $s1
    jal  draw_bitmap
print_board_ret:
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# print_board_rules() - print title and active king/capture ruleset banner
# -----------------------------------------------------------------------------
print_board_rules:
    print_str(str_pretty_title)
    print_str(str_pretty_kings)
    lw   $t0, opt_flying
    la   $a0, str_pretty_short
    beqz $t0, print_board_kings
    la   $a0, str_pretty_flying
print_board_kings:
    li   $v0, 4
    syscall
    print_str(str_pretty_cap)
    lw   $t0, opt_forced
    la   $a0, str_pretty_optional
    beqz $t0, print_board_capture_rule
    la   $a0, str_pretty_required
print_board_capture_rule:
    li   $v0, 4
    syscall
    jr   $ra

# -----------------------------------------------------------------------------
# print_board_plain(a0 = rotated?) - print specification's compact format:
#   8 lines, 8 space-separated cell characters per line.
# -----------------------------------------------------------------------------
print_board_plain:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    move $s2, $a0               # s2 = rotated flag
    li   $s0, 0                 # s0 = display row
print_plain_row:
    li   $s1, 0                 # s1 = display col
print_plain_col:
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    jal  view_index
    lbu  $a0, board($v0)
    li   $v0, 11
    syscall
    addi $s1, $s1, 1
    bge  $s1, 8, print_plain_eol
    print_char(' ')
    j    print_plain_col
print_plain_eol:
    print_char('\n')
    addi $s0, $s0, 1
    blt  $s0, 8, print_plain_row
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# print_board_pretty(a0 = upcoming side, a1 = rotated?)
# Renders framed position grid side-by-side with playable square numbers (in
# the active player's numbering) and live piece counts for both sides.
# -----------------------------------------------------------------------------
print_board_pretty:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a0               # s0 = viewing side
    move $s1, $a1               # s1 = rotated flag

    print_str(str_pretty_head1)
    li   $a0, SIDE_BLACK
    jal  count_pieces
    print_int_reg($v0)
    print_str(str_pretty_head2)
    li   $a0, SIDE_RED
    jal  count_pieces
    print_int_reg($v0)
    beqz $s1, print_pretty_top
    print_str(str_pretty_rot)
print_pretty_top:
    print_char('\n')
    print_str(str_pretty_cols)
    print_str(str_pretty_line)

    li   $s2, 0                 # s2 = display row
print_pretty_row:
    print_char(' ')
    print_char(' ')
    print_char('|')
    li   $s3, 0                 # s3 = display col
print_pretty_piece:             # left panel: board pieces
    move $a0, $s2
    move $a1, $s3
    move $a2, $s1
    jal  view_index
    lbu  $t0, board($v0)
    print_char(' ')
    beq  $t0, UNUSED, print_pretty_blank
    beq  $t0, EMPTY, print_pretty_dot
    print_char_reg($t0)
    j    print_pretty_piece_end
print_pretty_blank:
    print_char(' ')
    j    print_pretty_piece_end
print_pretty_dot:
    print_char('.')
print_pretty_piece_end:
    print_char(' ')
    print_char('|')
    addi $s3, $s3, 1
    blt  $s3, 8, print_pretty_piece

    print_str(str_pretty_gap)
    li   $s3, 0
print_pretty_number:            # right panel: playable square numbers
    move $a0, $s2
    move $a1, $s3
    move $a2, $s1
    jal  view_index
    lbu  $t0, board($v0)
    beq  $t0, UNUSED, print_pretty_nblank
    move $a0, $v0
    jal  idx_to_sq
    move $a0, $v0
    move $a1, $s0
    jal  view_square
    move $t1, $v0
    bge  $t1, 10, print_pretty_two
    print_char(' ')
print_pretty_two:
    print_int_reg($t1)
    print_char(' ')
    j    print_pretty_number_end
print_pretty_nblank:
    print_char(' ')
    print_char(' ')
    print_char(' ')
print_pretty_number_end:
    print_char('|')
    addi $s3, $s3, 1
    blt  $s3, 8, print_pretty_number

    print_char('\n')
    print_str(str_pretty_line)
    addi $s2, $s2, 1
    blt  $s2, 8, print_pretty_row
    print_str(str_pretty_foot)

    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# draw_bitmap(a0 = rotated?) - render board to MARS Bitmap Display.
# MARS setup: Tools > Bitmap Display, Unit Width/Height = 8,
# Display Width/Height = 512, Base address = 0x10040000 (heap), Connect to MIPS.
# Framebuffer is 64x64 units (8x8 per tile), 1 32-bit 0x00RRGGBB word per unit.
#
# Architectural optimizations:
#   1. Dirty-tile caching (bmp_cache[64]): redraws only modified tiles (2-3 per
#      move); forces a full 64-tile redraw on first draw, restart, or rotation.
#   2. Loop-Invariant Code Motion (LICM) + pointer stride: computes tile base
#      pointer once per tile, then advances +4 B/pixel and +224 B/row.
#   3. 8-way unrolled solid-tile fast path for empty/light tiles (+256 B/row).
#   4. Pipeline load-use scheduling: schedules independent instructions between
#      loads and dependent branches to eliminate inner-loop stalls.
# -----------------------------------------------------------------------------
draw_bitmap:
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    push($s5)
    push($s6)
    push($s7)
    move $s7, $a0               # s7 = rotated flag
    lw   $t8, bmp_valid
    lw   $t9, bmp_last_rot
    li   $s0, 0                 # s0 = display row (scheduled in load-use slot)
    beq  $t9, $s7, draw_bitmap_row
    li   $t8, 0                 # rotation changed -> force full 64-tile redraw
draw_bitmap_row:
    li   $s1, 0                 # s1 = display col (0..7)
draw_bitmap_col:
    sll  $t0, $s0, 3
    add  $t0, $t0, $s1
    move $t6, $t0               # t6 = display tile index (0..63)
    beqz $s7, draw_bitmap_cell
    li   $t1, 63
    sub  $t0, $t1, $t0          # rotated canonical index
draw_bitmap_cell:
    lbu  $t1, board($t0)
    beqz $t8, draw_bitmap_dirty
    lbu  $t2, bmp_cache($t6)
    beq  $t1, $t2, draw_bitmap_next_tile
draw_bitmap_dirty:
    sb   $t1, bmp_cache($t6)
    li   $s2, COLOR_DARK        # s2 = tile background color
    bne  $t1, UNUSED, draw_bitmap_piece
    li   $s2, COLOR_LIGHT
draw_bitmap_piece:
    li   $s3, 0                 # s3 = piece color (0 = empty)
    li   $s4, 0                 # s4 = king flag
    beq  $t1, PAWN_BLACK, draw_bitmap_black
    beq  $t1, KING_BLACK, draw_bitmap_bking
    beq  $t1, PAWN_RED, draw_bitmap_red
    beq  $t1, KING_RED, draw_bitmap_rking
    j    draw_bitmap_tile_init
draw_bitmap_bking:
    li   $s4, 1
draw_bitmap_black:
    li   $s3, COLOR_BLACK
    j    draw_bitmap_tile_init
draw_bitmap_rking:
    li   $s4, 1
draw_bitmap_red:
    li   $s3, COLOR_RED

draw_bitmap_tile_init:          # LICM: compute tile framebuffer base once
    sll  $t4, $s0, 9            # row * 8 * 64 = row * 512 words
    sll  $t5, $s1, 3            # col * 8 words
    add  $t4, $t4, $t5
    sll  $t4, $t4, 2            # byte offset
    li   $t5, BITMAP_BASE
    add  $t4, $t4, $t5          # t4 = framebuffer pointer for pixel (0,0)
    li   $s5, 0                 # s5 = pixel y (0..7)
    beqz $s3, draw_bitmap_solid_y
    la   $t5, piece_mask        # t5 = sequential pointer into 64B piece_mask
draw_bitmap_y:
    li   $s6, 0                 # s6 = pixel x (0..7)
draw_bitmap_x:
    lbu  $t3, 0($t5)            # load sprite mask byte
    addi $t5, $t5, 1            # scheduled in load-use delay slot (0 stall!)
    move $t2, $s2               # default: tile background RGB word
    beqz $t3, draw_bitmap_put
    move $t2, $s3
    bne  $t3, 2, draw_bitmap_put
    beqz $s4, draw_bitmap_put
    li   $t2, COLOR_KING
draw_bitmap_put:
    sw   $t2, 0($t4)
    addi $t4, $t4, 4            # stride +4 bytes to next pixel in row
    addi $s6, $s6, 1
    blt  $s6, 8, draw_bitmap_x
    addi $t4, $t4, 224          # stride +(64-8)*4 bytes to next tile row
    addi $s5, $s5, 1
    blt  $s5, 8, draw_bitmap_y
    j    draw_bitmap_next_tile

draw_bitmap_solid_y:            # 8-way unrolled fill for empty/light tiles
    sw   $s2, 0($t4)
    sw   $s2, 4($t4)
    sw   $s2, 8($t4)
    sw   $s2, 12($t4)
    sw   $s2, 16($t4)
    sw   $s2, 20($t4)
    sw   $s2, 24($t4)
    sw   $s2, 28($t4)
    addi $t4, $t4, 256          # stride +64*4 bytes to next row
    addi $s5, $s5, 1
    blt  $s5, 8, draw_bitmap_solid_y

draw_bitmap_next_tile:
    addi $s1, $s1, 1
    blt  $s1, 8, draw_bitmap_col
    addi $s0, $s0, 1
    blt  $s0, 8, draw_bitmap_row
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
