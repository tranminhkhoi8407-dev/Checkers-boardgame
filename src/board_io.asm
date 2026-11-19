###############################################################################
# board_io.asm - BÀN CỜ, HIỂN THỊ VÀ NHẬP LIỆU (phần phụ trách: Hậu)
#
#   - Lưu bàn cờ, khởi tạo đúng 12 quân mỗi bên.
#   - Đổi giữa số ô 1..32, (hàng, cột) và chỉ số mảng.
#   - In bàn cờ: kiểu chuẩn của đề, kiểu đẹp (khung + bảng số ô), xoay theo
#     người đang đi, và vẽ lên Bitmap Display của MARS.
#   - Đọc số an toàn: gõ chữ, để trống, số quá lớn... đều không làm crash.
#   - In thông báo lỗi (ngắn gọn hoặc chi tiết).
#
# File này được .include từ main.asm. Quy ước gọi hàm giống rules.asm.
###############################################################################

.data
# Bàn cờ 8x8, phần tử [r*8 + c]. '_' = ô trắng không dùng, '0' = ô tối trống.
board:          .space 64
start_board:    .ascii "_r_r_r_r"
                .ascii "r_r_r_r_"
                .ascii "_r_r_r_r"
                .ascii "0_0_0_0_"
                .ascii "_0_0_0_0"
                .ascii "b_b_b_b_"
                .ascii "_b_b_b_b"
                .ascii "b_b_b_b_"

# Mặt nạ quân cờ trong ô 8x8 điểm của Bitmap Display.
# 0 = nền, 1 = thân quân, 2 = hình vương miện (chỉ tô vàng cho vua).
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

# Câu giải thích cho từng mã lỗi (dùng khi bật "Detailed error messages")
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
# init_board() - chép thế cờ ban đầu (12 quân mỗi bên) vào board
# -----------------------------------------------------------------------------
init_board:
    li   $t0, 0
init_board_loop:
    lbu  $t1, start_board($t0)
    sb   $t1, board($t0)
    addi $t0, $t0, 1
    blt  $t0, 64, init_board_loop
    jr   $ra

# -----------------------------------------------------------------------------
# sq_to_rc(a0 = ô 1..32) -> v0 = hàng, v1 = cột
#   hàng = (s-1)/4 ; cột = 2*((s-1)%4) + (hàng chẵn ? 1 : 0)
# -----------------------------------------------------------------------------
sq_to_rc:
    addi $t0, $a0, -1
    srl  $v0, $t0, 2            # hàng = (s-1) / 4
    andi $t1, $t0, 3
    sll  $v1, $t1, 1            # 2 * ((s-1) % 4)
    andi $t2, $v0, 1
    xori $t2, $t2, 1            # hàng chẵn -> ô tối lệch sang phải 1 cột
    add  $v1, $v1, $t2
    jr   $ra

# -----------------------------------------------------------------------------
# idx_to_sq(a0 = chỉ số 0..63 của một ô tối) -> v0 = số ô 1..32
#   s = hàng*4 + cột/2 + 1
# -----------------------------------------------------------------------------
idx_to_sq:
    srl  $t0, $a0, 3            # hàng
    andi $t1, $a0, 7            # cột
    sll  $v0, $t0, 2
    srl  $t1, $t1, 1
    add  $v0, $v0, $t1
    addi $v0, $v0, 1
    jr   $ra

# -----------------------------------------------------------------------------
# get_cell(a0 = hàng, a1 = cột) -> v0 = ký tự trên bàn, hoặc 0 nếu ngoài bàn
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
# square_piece(a0 = ô 1..32) -> v0 = ký tự trên ô đó
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
# count_pieces(a0 = side) -> v0 = số quân (cả vua) còn lại của bên đó
# -----------------------------------------------------------------------------
count_pieces:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    move $s0, $a0
    li   $s1, 0                 # chỉ số ô
    li   $s2, 0                 # số quân
count_pieces_loop:
    lbu  $a0, board($s1)
    move $a1, $s0
    jal  is_own
    add  $s2, $s2, $v0
    addi $s1, $s1, 1
    blt  $s1, 64, count_pieces_loop
    move $v0, $s2
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# view_index(a0 = hàng hiển thị, a1 = cột hiển thị, a2 = có xoay?) -> v0 = chỉ số
# Xoay 180 độ: ô (r, c) hiện ở vị trí (7-r, 7-c), tức chỉ số 63 - i.
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
# board_rotated(a0 = side xem bàn) -> v0 = 1 nếu cần xoay bàn cho bên đó
# Khi Đỏ dùng số ô riêng, xoay luôn bàn để ô 29 ở góc dưới bên trái.
# -----------------------------------------------------------------------------
board_rotated:
    lw   $v0, opt_rotate
    lw   $t0, opt_relnum
    or   $v0, $v0, $t0
    and  $v0, $v0, $a0          # side Đỏ = 1
    jr   $ra

# -----------------------------------------------------------------------------
# view_square(a0 = số ô, a1 = side) -> v0 = số ô theo cách đánh số của side
# Khi bật "Player-relative numbering", Đỏ dùng số ô của riêng mình
# (ô 29 luôn ở góc dưới bên trái): số thật = 33 - số của Đỏ, và ngược lại.
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
# read_input_line() -> v0 = độ dài dòng, INPUT_INVALID, hoặc INPUT_END.
# Đọc từ stdin bằng syscall 14 để phát hiện EOF trên MARS CLI. Cùng syscall
# này đọc từ Run I/O trên MARS GUI. Giữ phần chưa đọc của mỗi khối cho lần sau.
# Nếu dòng quá dài, bỏ tới hết dòng để lần đọc sau vẫn bắt đầu đúng chỗ.
# -----------------------------------------------------------------------------
read_input_line:
    li   $t0, 0                 # độ dài dòng (bão hòa tại INPUT_SIZE + 1)
read_line_next:
    lw   $t1, input_next
    lw   $t2, input_end
    blt  $t1, $t2, read_line_byte
    li   $a0, 0                 # file descriptor stdin
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
    beqz $t0, read_line_eof       # một dòng cuối không có '\n' vẫn được xét
read_line_finish:
    li   $v0, INPUT_INVALID
    bgt  $t0, INPUT_SIZE, read_line_ret
    beqz $t0, read_line_terminate
    addi $t1, $t0, -1
    lbu  $t2, input_line($t1)
    bne  $t2, '\r', read_line_terminate
    move $t0, $t1               # bỏ CR cuối dòng để hỗ trợ CRLF
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
# read_number() -> v0 = số nguyên không âm, INPUT_INVALID, hoặc INPUT_END.
#
# Chấp nhận khoảng trắng ở đầu/cuối dòng. Số lớn hơn 9999 được giữ ở 9999.
# -----------------------------------------------------------------------------
read_number:
    push($ra)
    jal  read_input_line
    bltz $v0, read_number_ret
    la   $t0, input_line
    addu $t3, $t0, $v0          # cuối dòng thật, kể cả khi có byte NUL ở giữa
read_number_lead:               # bỏ khoảng trắng ở đầu
    lbu  $t1, 0($t0)
    beq  $t1, ' ', read_number_lead_next
    bne  $t1, '\t', read_number_digits_init
read_number_lead_next:
    addi $t0, $t0, 1
    j    read_number_lead
read_number_digits_init:
    li   $v0, 0                 # giá trị
    li   $t2, 0                 # số chữ số đã đọc
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
read_number_tail:               # sau số chỉ được có khoảng trắng
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
# read_square(a0 = side đang nhập) -> v0 = số ô thật (1..32), 0 (mở menu),
# hoặc mã kết thúc / giá trị không hợp lệ. Tự đổi cách đánh số của người chơi.
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
# print_side(a0 = side) - in "Black" hoặc "Red"
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
# print_error(a0 = mã lỗi) - báo nước đi không hợp lệ
# Mặc định in đúng câu của đề; khi bật "Detailed error messages" thì giải thích.
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
# print_board(a0 = side sắp đi) - in bàn cờ theo các tùy chọn đang bật
# -----------------------------------------------------------------------------
print_board:
    push($ra)
    push($s0)
    push($s1)
    move $s0, $a0
    jal  board_rotated
    move $s1, $v0               # s1 = có xoay bàn không
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
# print_board_rules() - hiển thị hai tùy chọn luật áp dụng cho bàn cờ hiện tại
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
# print_board_plain(a0 = có xoay?) - in đúng định dạng của đề:
#   8 dòng, mỗi dòng 8 ký tự cách nhau bởi dấu cách.
# -----------------------------------------------------------------------------
print_board_plain:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    move $s2, $a0               # s2 = có xoay?
    li   $s0, 0                 # s0 = hàng hiển thị
print_plain_row:
    li   $s1, 0                 # s1 = cột hiển thị
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
# print_board_pretty(a0 = side sắp đi, a1 = có xoay?)
# In bàn cờ có khung, bên cạnh là bảng số ô (theo cách đánh số của người chơi)
# và số quân còn lại của mỗi bên.
# -----------------------------------------------------------------------------
print_board_pretty:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a0               # s0 = side sắp đi
    move $s1, $a1               # s1 = có xoay?

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

    li   $s2, 0                 # s2 = hàng hiển thị
print_pretty_row:
    print_char(' ')
    print_char(' ')
    print_char('|')
    li   $s3, 0                 # s3 = cột hiển thị
print_pretty_piece:             # nửa trái: quân cờ
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
print_pretty_number:            # nửa phải: số ô
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
# draw_bitmap(a0 = có xoay?) - vẽ bàn cờ lên Bitmap Display của MARS.
# Cài đặt trong MARS: Tools > Bitmap Display, Unit Width/Height = 8,
# Display Width/Height = 512, Base address = 0x10040000 (heap), Connect to MIPS.
# Màn hình 64x64 điểm, mỗi ô cờ 8x8 điểm, mỗi điểm là một word màu 0x00RRGGBB.
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
    move $s7, $a0               # s7 = có xoay?
    li   $s0, 0                 # s0 = hàng hiển thị
draw_bitmap_row:
    li   $s1, 0                 # s1 = cột hiển thị
draw_bitmap_col:
    sll  $t0, $s0, 3            # chỉ số ô thật (giống view_index)
    add  $t0, $t0, $s1
    beqz $s7, draw_bitmap_cell
    li   $t1, 63
    sub  $t0, $t1, $t0
draw_bitmap_cell:
    lbu  $t1, board($t0)
    li   $s2, COLOR_DARK        # s2 = màu nền ô
    bne  $t1, UNUSED, draw_bitmap_piece
    li   $s2, COLOR_LIGHT
draw_bitmap_piece:
    li   $s3, 0                 # s3 = màu quân (0 = không có quân)
    li   $s4, 0                 # s4 = có phải vua?
    beq  $t1, PAWN_BLACK, draw_bitmap_black
    beq  $t1, KING_BLACK, draw_bitmap_bking
    beq  $t1, PAWN_RED, draw_bitmap_red
    beq  $t1, KING_RED, draw_bitmap_rking
    j    draw_bitmap_units
draw_bitmap_bking:
    li   $s4, 1
draw_bitmap_black:
    li   $s3, COLOR_BLACK
    j    draw_bitmap_units
draw_bitmap_rking:
    li   $s4, 1
draw_bitmap_red:
    li   $s3, COLOR_RED

draw_bitmap_units:              # tô 8x8 điểm của ô (y = s5, x = s6)
    li   $s5, 0
draw_bitmap_y:
    li   $s6, 0
draw_bitmap_x:
    move $t2, $s2               # t2 = màu của điểm
    beqz $s3, draw_bitmap_put
    sll  $t3, $s5, 3
    add  $t3, $t3, $s6
    lbu  $t3, piece_mask($t3)
    beqz $t3, draw_bitmap_put
    move $t2, $s3
    bne  $t3, 2, draw_bitmap_put
    beqz $s4, draw_bitmap_put
    li   $t2, COLOR_KING
draw_bitmap_put:
    sll  $t4, $s0, 3            # hàng điểm = hàng ô*8 + y
    add  $t4, $t4, $s5
    sll  $t4, $t4, 6            # * 64 điểm mỗi hàng
    sll  $t5, $s1, 3            # cột điểm = cột ô*8 + x
    add  $t5, $t5, $s6
    add  $t4, $t4, $t5
    sll  $t4, $t4, 2            # * 4 byte mỗi điểm
    li   $t5, BITMAP_BASE
    add  $t4, $t4, $t5
    sw   $t2, 0($t4)
    addi $s6, $s6, 1
    blt  $s6, 8, draw_bitmap_x
    addi $s5, $s5, 1
    blt  $s5, 8, draw_bitmap_y

    addi $s1, $s1, 1
    blt  $s1, 8, draw_bitmap_col
    addi $s0, $s0, 1
    blt  $s0, 8, draw_bitmap_row
    pop($s7)
    pop($s6)
    pop($s5)
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    jr   $ra
