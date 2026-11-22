###############################################################################
# defs.asm - SHARED CONSTANTS AND MACROS (Owner: Nguyen Thanh Hau)
# Included at the top of main.asm (and in test drivers under tests/unit/).
###############################################################################

# ============================ Constants ======================================
.eqv SIDE_BLACK     0
.eqv SIDE_RED       1

.eqv INVALID        0           # move classification
.eqv STEP           1
.eqv CAPTURE        2

.eqv EMPTY          48          # '0' empty dark square
.eqv UNUSED         95          # '_' unused light square
.eqv PAWN_BLACK     98          # 'b'
.eqv PAWN_RED       114         # 'r'
.eqv KING_BLACK     66          # 'B'
.eqv KING_RED       82          # 'R'

.eqv ERR_RANGE        1         # move error codes (messages in board_io.asm)
.eqv ERR_EMPTY        2
.eqv ERR_NOT_YOURS    3
.eqv ERR_OCCUPIED     4
.eqv ERR_NOT_DIAGONAL 5
.eqv ERR_BACKWARD     6
.eqv ERR_TOO_FAR      7
.eqv ERR_NO_ENEMY     8
.eqv ERR_MUST_CAPTURE 9
.eqv ERR_CHAIN        10
.eqv ERR_BLOCKED      11

.eqv RESULT_MOVED   0           # return status of play_turn / menu
.eqv RESULT_RESTART 1
.eqv RESULT_DRAW    2
.eqv RESULT_QUIT    3

.eqv NUM_OPTIONS    9           # number of toggleable settings in menu
.eqv HISTORY_MAX    1000        # maximum half-steps stored in move history
.eqv INPUT_SIZE     64          # input line buffer size (up to 63 chars/line)
.eqv INPUT_CHUNK_SIZE 256       # maximum bytes read per stdin chunk
.eqv INPUT_INVALID  -1          # syntax error or overlong input line
.eqv INPUT_END      -2          # stdin EOF or read failure

.eqv BITMAP_BASE    0x10040000  # heap base address for MARS Bitmap Display
.eqv COLOR_LIGHT    0x00EFE3CA
.eqv COLOR_DARK     0x00567772
.eqv COLOR_BLACK    0x00212C45
.eqv COLOR_RED      0x00BE3448
.eqv COLOR_KING     0x00F1C972

# ============================ Macros =========================================
# All macros below modify only $a0 and $v0.
.macro print_str (%label)
    la   $a0, %label
    li   $v0, 4
    syscall
.end_macro

.macro print_char (%c)
    li   $a0, %c
    li   $v0, 11
    syscall
.end_macro

.macro print_char_reg (%reg)
    move $a0, %reg
    li   $v0, 11
    syscall
.end_macro

.macro print_int_reg (%reg)
    move $a0, %reg
    li   $v0, 1
    syscall
.end_macro

.macro push (%reg)
    addi $sp, $sp, -4
    sw   %reg, 0($sp)
.end_macro

.macro pop (%reg)
    lw   %reg, 0($sp)
    addi $sp, $sp, 4
.end_macro
