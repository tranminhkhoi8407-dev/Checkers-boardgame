###############################################################################
# Checkers (English draughts) - MARS MIPS Assembly
# CO2008 - Computer Architecture Lab
#
# main.asm - ĐIỀU KHIỂN CHƯƠNG TRÌNH (phần phụ trách: Hậu)
#   Vòng lặp chính, lượt chơi, đổi lượt, kết thúc ván, menu cài đặt và các
#   tính năng thêm (lịch sử nước đi, xin hòa, chơi lại). Ghép các file khác
#   bằng .include:
#     defs.asm      hằng số và macro dùng chung        (Hậu)
#     board_io.asm  bàn cờ, hiển thị, nhập liệu        (Hậu)
#     rules.asm     luật đi, ăn quân, phong vua          (Khôi)
#
# Chạy:  java -jar Mars45.jar nc src/main.asm
#        hoặc mở src/main.asm trong MARS rồi Assemble (tắt tùy chọn
#        "Assemble all files in directory" để không bị trùng nhãn).
#
# Mặc định hiển thị bàn cờ có khung và số ô. Nhập 0 ở ô xuất phát để mở menu.
# Thêm "pa classic" vào cuối lệnh CLI để phát lại transcript của ván mẫu.
###############################################################################

# Hằng số (.eqv) và macro dùng chung
.include "defs.asm"

# ============================ Dữ liệu ========================================
.data
turn:           .word SIDE_BLACK    # bên đang đi
draw_offer:     .word -1            # bên đang xin hòa (-1 = không ai)
history_len:    .word 0

# Các tùy chọn bật/tắt (thứ tự giống menu, 0 = tắt, 1 = bật)
options:
opt_pretty:     .word 1     # 1. bàn cờ có khung và số ô
opt_rotate:     .word 0     # 2. xoay bàn cho lượt Đỏ
opt_relnum:     .word 0     # 3. Đỏ dùng cách đánh số của mình
opt_detail:     .word 0     # 4. thông báo lỗi chi tiết
opt_hints:      .word 0     # 5. gợi ý nước đi
opt_forced:     .word 0     # 6. bắt buộc ăn quân
opt_flying:     .word 0     # 7. vua bay
opt_bitmap:     .word 0     # 8. vẽ lên Bitmap Display
opt_replay:     .word 0     # 9. hỏi chơi lại khi hết ván

# Lịch sử: mỗi bước 4 byte = ô đi, ô đến, cờ (bit0 = ăn, bit1 = ăn tiếp), bên đi
history:        .space 4000

str_black_turn: .asciiz "Black's turn.\n"
str_red_turn:   .asciiz "Red's turn.\n"
str_ask_start:  .asciiz "Enter starting square: "
str_ask_land:   .asciiz "Enter landing square: "
str_cap_red:    .asciiz "Captured Red's piece.\n"
str_cap_black:  .asciiz "Captured Black's piece.\n"
str_chain:      .asciiz "Chaining possible.\n"
str_chain_piece:.asciiz "  Continue with the piece on square "
str_black_wins: .asciiz "Black wins!\n"
str_red_wins:   .asciiz "Red wins!\n"

str_no_moves:   .asciiz " has no legal moves left.\n"
str_no_pieces:  .asciiz " has no pieces left.\n"
str_classic_arg:.asciiz "classic"
str_draw_end:   .asciiz "Both players agreed to a draw. Game over.\n"
str_replay:     .asciiz "Play again? Type 1 for a new game, anything else to quit: "
str_bye:        .asciiz "Goodbye!\n"
str_restart:    .asciiz "\nStarting a new game...\n"

str_hint_pieces:.asciiz "  Pieces that can move:"
str_hint_lands: .asciiz "  Possible landing squares:"
str_hint_none:  .asciiz " none - choose another piece."
str_must_cap:   .asciiz "  A capture is available: you must capture.\n"

str_draw_wait:  .asciiz " offers a draw. Open the menu (0) and choose 11 to accept, or make a move to decline.\n"
str_draw_offer: .asciiz " offers a draw. Your opponent can accept it from the menu on their turn.\n"
str_draw_again: .asciiz "You have already offered a draw.\n"
str_draw_no:    .asciiz "Draw offer declined.\n"

str_hist_head:  .asciiz "\nMove history (standard notation, Black's numbering):"
str_hist_empty: .asciiz "\n  (no moves yet)"
str_hist_dot:   .asciiz ". "

str_menu_head:  .asciiz "\n=============== MENU ===============\nSettings (type the number to switch ON/OFF):\n"
str_menu_on:    .asciiz "ON\n"
str_menu_off:   .asciiz "OFF\n"
str_menu_actions: .asciiz "Actions:\n 10. Show move history\n 11. Offer / accept a draw\n 12. Restart the game\n 13. Quit\n 14. Turn on all quality-of-life options (1-5, 9)\n  0. Back to the game\nYour choice: "
str_menu_bad:   .asciiz "Unknown choice.\n"
str_menu_all:   .asciiz "Quality-of-life options turned on.\n"
option_labels:  .word opt_txt1, opt_txt2, opt_txt3, opt_txt4, opt_txt5, opt_txt6, opt_txt7, opt_txt8, opt_txt9
opt_txt1:       .asciiz "  1. Pretty board (frame + square numbers) ... "
opt_txt2:       .asciiz "  2. Rotate Red with standard numbering ..... "
opt_txt3:       .asciiz "  3. Red's own numbers (also rotates Red) ... "
opt_txt4:       .asciiz "  4. Detailed error messages ................. "
opt_txt5:       .asciiz "  5. Move hints (list legal moves) ........... "
opt_txt6:       .asciiz "  6. Forced capture rule ..................... "
opt_txt7:       .asciiz "  7. Flying kings variant .................... "
opt_txt8:       .asciiz "  8. Bitmap Display (setup: see README) ...... "
opt_txt9:       .asciiz "  9. Ask to play again when the game ends .... "

# ============================ Chương trình ===================================
.text
.globl main

# -----------------------------------------------------------------------------
# main - vòng lặp chính của ván cờ
#   Đen đi trước. Trước mỗi lượt kiểm tra bên tới lượt còn nước đi không
#   (hết quân hoặc bị chặn hết thì thua). Sau mỗi lượt hợp lệ mới đổi lượt.
# -----------------------------------------------------------------------------
main:
    # MARS CLI: "pa classic" khởi động với bàn cờ gọn để phát lại ván mẫu.
    beqz $a0, main_new_game
    lw   $t0, 0($a1)
    la   $t1, str_classic_arg
main_arg_check:
    lbu  $t2, 0($t0)
    lbu  $t3, 0($t1)
    bne  $t2, $t3, main_new_game
    beqz $t2, main_classic
    addiu $t0, $t0, 1
    addiu $t1, $t1, 1
    j    main_arg_check
main_classic:
    sw   $zero, opt_pretty
main_new_game:
    jal  new_game
    li   $a0, SIDE_BLACK
    jal  print_board
main_loop:
    lw   $a0, turn
    jal  has_any_move
    beqz $v0, main_no_moves
    jal  play_turn
    beq  $v0, RESULT_RESTART, main_restart
    beq  $v0, RESULT_DRAW, main_draw
    beq  $v0, RESULT_QUIT, main_exit
    lw   $t0, turn              # đổi lượt chỉ sau khi đi xong một nước hợp lệ
    xori $t0, $t0, 1
    sw   $t0, turn
    j    main_loop

main_no_moves:                  # bên tới lượt thua
    lw   $t0, opt_pretty
    bnez $t0, main_loss_reason
    lw   $t0, opt_detail
    beqz $t0, main_announce
main_loss_reason:
    lw   $a0, turn
    jal  count_pieces
    beqz $v0, main_no_pieces
    lw   $a0, turn
    jal  print_side
    print_str(str_no_moves)
    j    main_announce
main_no_pieces:
    lw   $a0, turn
    jal  print_side
    print_str(str_no_pieces)
main_announce:
    lw   $t0, turn
    la   $a0, str_red_wins
    beqz $t0, main_announce_print
    la   $a0, str_black_wins
main_announce_print:
    li   $v0, 4
    syscall
    j    main_game_over

main_draw:
    print_str(str_draw_end)
main_game_over:
    lw   $t0, opt_replay
    beqz $t0, main_exit
    print_str(str_replay)
    jal  read_number
    bne  $v0, 1, main_quit_msg
main_restart:
    print_str(str_restart)
    j    main_new_game
main_quit_msg:
    print_str(str_bye)
main_exit:
    li   $v0, 10
    syscall

# -----------------------------------------------------------------------------
# new_game() - đặt lại bàn cờ, lượt đi, lời xin hòa và lịch sử
# -----------------------------------------------------------------------------
new_game:
    push($ra)
    jal  init_board
    sw   $zero, turn
    li   $t0, -1
    sw   $t0, draw_offer
    sw   $zero, history_len
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# play_turn() -> v0 = RESULT_MOVED | RESULT_RESTART | RESULT_DRAW | RESULT_QUIT
#
# Một lượt đi của bên "turn":
#   1. Hỏi ô xuất phát và ô đích (0 ở ô xuất phát = mở menu).
#   2. Nước sai -> báo lỗi, hỏi lại; người chơi KHÔNG mất lượt.
#   3. Đi thường -> in bàn cờ, hết lượt.
#   4. Ăn quân -> in bàn cờ; nếu quân vừa ăn còn ăn tiếp được thì bắt buộc
#      ăn liên hoàn: chỉ hỏi lại ô đích cho tới khi hết nước ăn.
# -----------------------------------------------------------------------------
play_turn:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    lw   $s3, turn              # s3 = bên đang đi

play_turn_begin:
    la   $a0, str_black_turn
    beqz $s3, play_turn_header
    la   $a0, str_red_turn
play_turn_header:
    li   $v0, 4
    syscall
    jal  notify_draw_offer
    lw   $t0, opt_hints
    beqz $t0, play_turn_ask_start
    move $a0, $s3
    jal  print_movable_pieces

play_turn_ask_start:
    print_str(str_ask_start)
    move $a0, $s3
    jal  read_square
    beq  $v0, INPUT_END, play_turn_input_end
    beqz $v0, play_turn_menu
    move $s0, $v0               # s0 = ô xuất phát
    blt  $s0, 1, play_turn_bad_number
    bgt  $s0, 32, play_turn_bad_number

    # Bật lỗi chi tiết hoặc gợi ý: kiểm tra ô xuất phát ngay, chưa hỏi ô đích
    lw   $t0, opt_detail
    lw   $t1, opt_hints
    or   $t0, $t0, $t1
    beqz $t0, play_turn_ask_land
    move $a0, $s0
    move $a1, $s3
    jal  check_start
    beqz $v0, play_turn_start_ok
    move $a0, $v0
    jal  print_error
    j    play_turn_ask_start
play_turn_start_ok:
    lw   $t0, opt_hints
    beqz $t0, play_turn_ask_land
    move $a0, $s0
    move $a1, $s3
    li   $a2, 0
    jal  print_landing_squares
    beqz $v0, play_turn_ask_start   # quân này không đi được -> chọn quân khác

play_turn_ask_land:
    print_str(str_ask_land)
    move $a0, $s3
    jal  read_square
    beq  $v0, INPUT_END, play_turn_input_end
    move $s1, $v0               # s1 = ô đích
    move $a0, $s0
    move $a1, $s1
    move $a2, $s3
    jal  validate_move
    bnez $v0, play_turn_valid
    move $a0, $v1
    jal  print_error
    j    play_turn_ask_start

play_turn_valid:
    move $s2, $v0               # s2 = loại nước (STEP / CAPTURE)
    move $a0, $s0
    move $a1, $s1
    jal  do_move
    seq  $a2, $s2, CAPTURE
    move $a0, $s0
    move $a1, $s1
    move $a3, $s3
    jal  record_move
    jal  decline_draw_offer
    beq  $s2, CAPTURE, play_turn_captured
    xori $a0, $s3, 1            # bàn cờ hiện theo góc nhìn của bên sắp đi
    jal  print_board
    li   $v0, RESULT_MOVED
    j    play_turn_ret

play_turn_captured:             # s1 = ô quân vừa ăn đang đứng
    la   $a0, str_cap_red
    beqz $s3, play_turn_cap_msg
    la   $a0, str_cap_black
play_turn_cap_msg:
    li   $v0, 4
    syscall
    move $a0, $s1               # đọc quân ở ô mới sau do_move (có thể đã là vua)
    move $a1, $s3
    jal  can_capture_from
    move $s4, $v0               # s4 = còn ăn tiếp được không
    xori $a0, $s3, 1
    beqz $s4, play_turn_cap_board
    move $a0, $s3               # còn ăn tiếp: vẫn là lượt của bên này
play_turn_cap_board:
    jal  print_board
    li   $v0, RESULT_MOVED
    beqz $s4, play_turn_ret

    print_str(str_chain)
    lw   $t0, opt_pretty
    beqz $t0, play_turn_chain_hints
    print_str(str_chain_piece)
    move $a0, $s1
    move $a1, $s3
    jal  view_square
    print_int_reg($v0)
    print_char(46)
    print_char(10)
play_turn_chain_hints:
    lw   $t0, opt_hints
    beqz $t0, play_turn_chain_ask
    move $a0, $s1
    move $a1, $s3
    li   $a2, 1
    jal  print_landing_squares
play_turn_chain_ask:
    print_str(str_ask_land)
    move $a0, $s3
    jal  read_square
    beq  $v0, INPUT_END, play_turn_input_end
    move $s0, $v0               # s0 = ô đích của bước ăn tiếp
    move $a0, $s1
    move $a1, $s0
    move $a2, $s3
    jal  validate_chain
    bnez $v0, play_turn_chain_ok
    move $a0, $v1
    jal  print_error
    j    play_turn_chain_ask
play_turn_chain_ok:
    move $a0, $s1
    move $a1, $s0
    jal  do_move
    move $a0, $s1
    move $a1, $s0
    li   $a2, 3                 # ăn + là bước nối tiếp
    move $a3, $s3
    jal  record_move
    move $s1, $s0
    j    play_turn_captured

play_turn_menu:
    jal  menu
    bnez $v0, play_turn_ret
    move $a0, $s3
    jal  print_board
    j    play_turn_begin

play_turn_bad_number:
    li   $a0, ERR_RANGE
    jal  print_error
    j    play_turn_ask_start

play_turn_input_end:
    li   $v0, RESULT_QUIT
play_turn_ret:
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# print_movable_pieces(a0 = side) - gợi ý: liệt kê các quân đi được
# (theo cách đánh số của người chơi; đã tính luật bắt buộc ăn nếu bật)
# -----------------------------------------------------------------------------
print_movable_pieces:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a0               # s0 = side
    lw   $t0, opt_forced
    beqz $t0, print_movable_list
    jal  side_has_capture
    beqz $v0, print_movable_list
    print_str(str_must_cap)
print_movable_list:
    print_str(str_hint_pieces)
    li   $s1, 1                 # s1 = số ô người chơi nhìn thấy
print_movable_loop:
    move $a0, $s1
    move $a1, $s0
    jal  view_square
    move $s2, $v0               # s2 = ô thật
    move $a0, $s2
    move $a1, $s0
    jal  check_start
    bnez $v0, print_movable_next
    li   $s3, 1                 # s3 = ô đích thử
print_movable_try:
    move $a0, $s2
    move $a1, $s3
    move $a2, $s0
    jal  validate_move
    bnez $v0, print_movable_show
    addi $s3, $s3, 1
    ble  $s3, 32, print_movable_try
    j    print_movable_next
print_movable_show:
    print_char(' ')
    print_int_reg($s1)
print_movable_next:
    addi $s1, $s1, 1
    ble  $s1, 32, print_movable_loop
    print_char('\n')
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# print_landing_squares(a0 = ô quân, a1 = side, a2 = 1 nếu đang ăn liên hoàn)
#   -> v0 = số ô đích hợp lệ. Gợi ý: liệt kê nơi quân đó có thể đến.
# -----------------------------------------------------------------------------
print_landing_squares:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    move $s0, $a0               # s0 = ô quân
    move $s1, $a1               # s1 = side
    move $s2, $a2               # s2 = đang ăn liên hoàn?
    li   $s3, 1                 # s3 = số ô người chơi nhìn thấy
    li   $s4, 0                 # s4 = đếm
    print_str(str_hint_lands)
print_landing_loop:
    move $a0, $s3
    move $a1, $s1
    jal  view_square
    move $a0, $s0
    move $a1, $v0
    move $a2, $s1
    bnez $s2, print_landing_chain
    jal  validate_move
    j    print_landing_check
print_landing_chain:
    jal  validate_chain
print_landing_check:
    beqz $v0, print_landing_next
    addi $s4, $s4, 1
    print_char(' ')
    print_int_reg($s3)
print_landing_next:
    addi $s3, $s3, 1
    ble  $s3, 32, print_landing_loop
    bnez $s4, print_landing_end
    print_str(str_hint_none)
print_landing_end:
    print_char('\n')
    move $v0, $s4
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# record_move(a0 = ô đi, a1 = ô đến, a2 = cờ, a3 = side) - lưu một bước vào lịch sử
#   cờ: bit0 = nước ăn, bit1 = bước nối tiếp trong chuỗi ăn liên hoàn
# -----------------------------------------------------------------------------
record_move:
    lw   $t0, history_len
    bge  $t0, HISTORY_MAX, record_move_ret
    sll  $t1, $t0, 2
    sb   $a0, history($t1)
    addi $t1, $t1, 1
    sb   $a1, history($t1)
    addi $t1, $t1, 1
    sb   $a2, history($t1)
    addi $t1, $t1, 1
    sb   $a3, history($t1)
    addi $t0, $t0, 1
    sw   $t0, history_len
record_move_ret:
    jr   $ra

# -----------------------------------------------------------------------------
# print_history() - in lịch sử theo ký hiệu chuẩn, mỗi lượt một dòng:
#     1. Black 21-17
#     2. Red 9-14
#     3. Black 22x15 15x8
# -----------------------------------------------------------------------------
print_history:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    print_str(str_hist_head)
    lw   $t0, history_len
    bnez $t0, print_history_start
    print_str(str_hist_empty)
print_history_start:
    li   $s0, 0                 # s0 = chỉ số bước
    li   $s1, 0                 # s1 = số thứ tự lượt
print_history_loop:
    lw   $t0, history_len
    bge  $s0, $t0, print_history_end
    sll  $s2, $s0, 2            # s2 = địa chỉ tương đối của bước
    lbu  $t1, history+2($s2)
    andi $t1, $t1, 2
    bnez $t1, print_history_step    # bước nối tiếp: in tiếp trên cùng dòng
    addi $s1, $s1, 1
    print_char('\n')
    print_char(' ')
    print_char(' ')
    print_int_reg($s1)
    print_str(str_hist_dot)
    lbu  $a0, history+3($s2)
    jal  print_side
print_history_step:
    print_char(' ')
    lbu  $t1, history($s2)
    print_int_reg($t1)
    lbu  $t1, history+2($s2)
    andi $t1, $t1, 1
    li   $a0, '-'
    beqz $t1, print_history_sep
    li   $a0, 'x'
print_history_sep:
    li   $v0, 11
    syscall
    lbu  $t1, history+1($s2)
    print_int_reg($t1)
    addi $s0, $s0, 1
    j    print_history_loop
print_history_end:
    print_char('\n')
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# notify_draw_offer() - đầu lượt, báo nếu đối phương đang xin hòa
# -----------------------------------------------------------------------------
notify_draw_offer:
    push($ra)
    lw   $t0, draw_offer
    lw   $t1, turn
    xori $t1, $t1, 1
    bne  $t0, $t1, notify_draw_ret
    move $a0, $t0
    jal  print_side
    print_str(str_draw_wait)
notify_draw_ret:
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# decline_draw_offer() - bên được mời hòa đã đi một nước, coi như từ chối
# -----------------------------------------------------------------------------
decline_draw_offer:
    lw   $t0, draw_offer
    lw   $t1, turn
    xori $t1, $t1, 1
    bne  $t0, $t1, decline_draw_ret
    li   $t0, -1
    sw   $t0, draw_offer
    print_str(str_draw_no)
decline_draw_ret:
    jr   $ra

# -----------------------------------------------------------------------------
# menu() -> v0 = RESULT_MOVED (quay lại ván), RESULT_RESTART, RESULT_DRAW, RESULT_QUIT
# Bật/tắt tùy chọn 1..9 và các thao tác 10..14.
# -----------------------------------------------------------------------------
menu:
    push($ra)
    push($s0)
menu_show:
    print_str(str_menu_head)
    li   $s0, 0                 # s0 = chỉ số tùy chọn (0..8)
menu_option_loop:
    sll  $t0, $s0, 2
    lw   $a0, option_labels($t0)
    li   $v0, 4
    syscall
    sll  $t0, $s0, 2
    lw   $t1, options($t0)
    la   $a0, str_menu_off
    beqz $t1, menu_option_state
    la   $a0, str_menu_on
menu_option_state:
    li   $v0, 4
    syscall
    addi $s0, $s0, 1
    blt  $s0, NUM_OPTIONS, menu_option_loop
    print_str(str_menu_actions)
    jal  read_number
    beq  $v0, INPUT_END, menu_input_end
    move $s0, $v0

    beqz $s0, menu_back
    blt  $s0, 1, menu_bad
    bgt  $s0, NUM_OPTIONS, menu_action
    addi $t0, $s0, -1           # bật/tắt tùy chọn số s0
    sll  $t0, $t0, 2
    lw   $t1, options($t0)
    xori $t1, $t1, 1
    sw   $t1, options($t0)
    j    menu_show

menu_action:
    beq  $s0, 10, menu_history
    beq  $s0, 11, menu_draw
    beq  $s0, 12, menu_restart
    beq  $s0, 13, menu_quit
    beq  $s0, 14, menu_all
menu_bad:
    print_str(str_menu_bad)
    j    menu_show

menu_history:
    jal  print_history
    j    menu_show

menu_draw:
    lw   $t0, draw_offer
    lw   $t1, turn
    xori $t2, $t1, 1
    beq  $t0, $t2, menu_draw_accept     # đối phương đã xin hòa -> hòa
    bne  $t0, $t1, menu_draw_new
    print_str(str_draw_again)
    j    menu_show
menu_draw_new:
    sw   $t1, draw_offer
    move $a0, $t1
    jal  print_side
    print_str(str_draw_offer)
    j    menu_show
menu_draw_accept:
    li   $v0, RESULT_DRAW
    j    menu_ret

menu_restart:                   # main in thông báo và tạo ván mới
    li   $v0, RESULT_RESTART
    j    menu_ret

menu_quit:
    print_str(str_bye)
menu_input_end:
    li   $v0, RESULT_QUIT
    j    menu_ret

menu_all:                       # bật các tùy chọn tiện ích 1-5 và 9
    li   $t0, 1
    sw   $t0, opt_pretty
    sw   $t0, opt_rotate
    sw   $t0, opt_relnum
    sw   $t0, opt_detail
    sw   $t0, opt_hints
    sw   $t0, opt_replay
    print_str(str_menu_all)
    j    menu_show

menu_back:
    li   $v0, RESULT_MOVED
menu_ret:
    pop($s0)
    pop($ra)
    jr   $ra

# ============================ Ghép các phần khác =============================
.include "board_io.asm"
.include "rules.asm"
