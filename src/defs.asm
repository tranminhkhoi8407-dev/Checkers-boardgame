###############################################################################
# defs.asm - HẰNG SỐ VÀ MACRO DÙNG CHUNG (phần phụ trách: Hậu)
# Được .include ở đầu main.asm (và ở các file test trong tests/unit).
###############################################################################

# ============================ Hằng số ========================================
.eqv SIDE_BLACK     0
.eqv SIDE_RED       1

.eqv INVALID        0           # loại nước đi
.eqv STEP           1
.eqv CAPTURE        2

.eqv EMPTY          48          # '0' ô tối trống
.eqv UNUSED         95          # '_' ô trắng không dùng
.eqv PAWN_BLACK     98          # 'b'
.eqv PAWN_RED       114         # 'r'
.eqv KING_BLACK     66          # 'B'
.eqv KING_RED       82          # 'R'

.eqv ERR_RANGE        1         # mã lỗi nước đi (câu giải thích ở board_io.asm)
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

.eqv RESULT_MOVED   0           # kết quả của play_turn / menu
.eqv RESULT_RESTART 1
.eqv RESULT_DRAW    2
.eqv RESULT_QUIT    3

.eqv NUM_OPTIONS    9           # số tùy chọn bật/tắt trong menu
.eqv HISTORY_MAX    1000        # số bước tối đa lưu trong lịch sử
.eqv INPUT_SIZE     64          # kích thước bộ đệm nhập

.eqv BITMAP_BASE    0x10040000  # vùng heap, dùng làm bộ nhớ Bitmap Display
.eqv COLOR_LIGHT    0x00F4F1EA
.eqv COLOR_DARK     0x0064788A
.eqv COLOR_BLACK    0x0017181A
.eqv COLOR_RED      0x00E02B20
.eqv COLOR_KING     0x00E6C063

# ============================ Macro ==========================================
# Các macro dưới đây chỉ dùng $a0 và $v0.
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
