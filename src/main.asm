###############################################################################
# Checkers (English draughts) - MARS MIPS Assembly
# CO2008 - Computer Architecture Lab
#
# main.asm - PROGRAM CONTROLLER (Owner: Nguyen Thanh Hau)
#   Main game loop, turn execution, turn switching, win/draw handling, settings
#   menu, and extra features (move history, draw offer, replay). Assembles all
#   modules into one translation unit via .include:
#     defs.asm      shared constants and macros             (Nguyen Thanh Hau)
#     board_io.asm  board state, rendering, input parsing   (Nguyen Thanh Hau)
#     rules.asm     move validation, captures, promotion    (Tran Minh Khoi)
#
# Run:  java -jar Mars45.jar nc src/main.asm
#       or open src/main.asm in MARS GUI and assemble (disable
#       "Assemble all files in directory" to avoid duplicate-label errors).
#
# Defaults to the framed board with square numbers. Enter 0 at the starting-
# square prompt to open the menu. Pass "pa classic" on the CLI to replay
# classic transcript fixtures.
###############################################################################

# Shared constants (.eqv) and utility macros
.include "defs.asm"

# ============================ Data Segment ===================================
.data
turn:           .word SIDE_BLACK    # active side (0 = Black, 1 = Red)
draw_offer:     .word -1            # side offering a draw (-1 = none)
history_len:    .word 0

# Toggleable settings (same order as menu; 0 = OFF, 1 = ON)
options:
opt_pretty:     .word 1     # 1. framed board with square numbers
opt_rotate:     .word 0     # 2. rotate board on Red's turn
opt_relnum:     .word 0     # 3. Red's player-relative square numbering
opt_detail:     .word 0     # 4. detailed error messages
opt_hints:      .word 0     # 5. legal move hints
opt_forced:     .word 0     # 6. forced first capture rule
opt_flying:     .word 0     # 7. flying kings variant
opt_bitmap:     .word 0     # 8. render to MARS Bitmap Display
opt_replay:     .word 0     # 9. prompt to play again after game over

# Move history: 4 bytes/step = from, to, flags (bit0=capture, bit1=chain), side
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

# ============================ Code Segment ===================================
.text
.globl main

# -----------------------------------------------------------------------------
# main - primary game loop
#   Black moves first. Before each turn, checks whether the active side has at
#   least one legal move (elimination or full blockade ends the game). Turn
#   switches only after a valid move (and any mandatory capture chain).
# -----------------------------------------------------------------------------
main:
    # MARS CLI: "pa classic" starts with the compact board for transcript tests.
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
    lw   $t0, turn              # switch turn only after completing a legal move
    xori $t0, $t0, 1
    sw   $t0, turn
    j    main_loop

main_no_moves:                  # active side has no legal move and loses
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
# new_game() - reset board, active turn, draw offer state, and move history
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
# Executes one turn for the active side stored in "turn":
#   1. Prompt for starting and landing squares (0 at start opens the menu).
#   2. Invalid move -> print error and re-prompt; player does NOT lose turn.
#   3. Normal step -> render board and end turn.
#   4. Capture -> render board; if the capturing piece can jump again, enforce
#      mandatory chain capture by prompting only for the next landing square.
# -----------------------------------------------------------------------------
play_turn:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    lw   $s3, turn              # s3 = active side

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
    move $s0, $v0               # s0 = starting square
    blt  $s0, 1, play_turn_bad_number
    bgt  $s0, 32, play_turn_bad_number

    # Detailed errors or hints enabled: validate starting square immediately
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
    beqz $v0, play_turn_ask_start   # selected piece has no legal moves

play_turn_ask_land:
    print_str(str_ask_land)
    move $a0, $s3
    jal  read_square
    beq  $v0, INPUT_END, play_turn_input_end
    move $s1, $v0               # s1 = landing square
    move $a0, $s0
    move $a1, $s1
    move $a2, $s3
    jal  validate_move
    bnez $v0, play_turn_valid
    move $a0, $v1
    jal  print_error
    j    play_turn_ask_start

play_turn_valid:
    move $s2, $v0               # s2 = move type (STEP / CAPTURE)
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
    xori $a0, $s3, 1            # display board from next player's perspective
    jal  print_board
    li   $v0, RESULT_MOVED
    j    play_turn_ret

play_turn_captured:             # s1 = landing square of capturing piece
    la   $a0, str_cap_red
    beqz $s3, play_turn_cap_msg
    la   $a0, str_cap_black
play_turn_cap_msg:
    li   $v0, 4
    syscall
    move $a0, $s1               # re-read piece after do_move (may be newly crowned)
    move $a1, $s3
    jal  can_capture_from
    move $s4, $v0               # s4 = 1 if chain capture continues
    xori $a0, $s3, 1
    beqz $s4, play_turn_cap_board
    move $a0, $s3               # chain continues: keep current player's view
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
    move $s0, $v0               # s0 = landing square of chain continuation
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
    li   $a2, 3                 # flags: bit0 = capture, bit1 = chain continuation
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
# print_movable_pieces(a0 = side) - hints: list all pieces with a legal move
# (uses active player's numbering; respects forced capture when enabled)
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
    li   $s1, 1                 # s1 = displayed square number
print_movable_loop:
    move $a0, $s1
    move $a1, $s0
    jal  view_square
    move $s2, $v0               # s2 = canonical square number
    move $a0, $s2
    move $a1, $s0
    jal  check_start
    bnez $v0, print_movable_next
    li   $s3, 1                 # s3 = candidate landing square
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
# print_landing_squares(a0 = piece square, a1 = side, a2 = 1 if chaining)
#   -> v0 = count of legal landing squares. Lists valid destinations for piece.
# -----------------------------------------------------------------------------
print_landing_squares:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    move $s0, $a0               # s0 = canonical starting square
    move $s1, $a1               # s1 = side
    move $s2, $a2               # s2 = chaining flag
    li   $s3, 1                 # s3 = displayed landing square number
    li   $s4, 0                 # s4 = legal destination counter
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
# record_move(a0 = from, a1 = to, a2 = flags, a3 = side) - append step to history
#   flags: bit0 = capture, bit1 = chain continuation step
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
# print_history() - print move history in standard notation, one line per turn:
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
    li   $s0, 0                 # s0 = step index
    li   $s1, 0                 # s1 = turn counter
print_history_loop:
    lw   $t0, history_len
    bge  $s0, $t0, print_history_end
    sll  $s2, $s0, 2            # s2 = byte offset into history
    lbu  $t1, history+2($s2)
    andi $t1, $t1, 2
    bnez $t1, print_history_step    # chain step: append to current line
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
# notify_draw_offer() - at start of turn, notify if opponent offered a draw
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
# decline_draw_offer() - making a move implicitly declines a pending draw offer
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
# menu() -> v0 = RESULT_MOVED (resume game), RESULT_RESTART, RESULT_DRAW, RESULT_QUIT
# Toggles settings 1..9 and handles actions 10..14.
# -----------------------------------------------------------------------------
menu:
    push($ra)
    push($s0)
menu_show:
    print_str(str_menu_head)
    li   $s0, 0                 # s0 = option index (0..8)
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
    addi $t0, $s0, -1           # toggle option s0
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
    beq  $t0, $t2, menu_draw_accept     # opponent offered draw -> mutual draw
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

menu_restart:                   # main prints restart message and resets game
    li   $v0, RESULT_RESTART
    j    menu_ret

menu_quit:
    print_str(str_bye)
menu_input_end:
    li   $v0, RESULT_QUIT
    j    menu_ret

menu_all:                       # enable all quality-of-life options (1-5, 9)
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

# ============================ Included Modules ===============================
.include "board_io.asm"
.include "rules.asm"
