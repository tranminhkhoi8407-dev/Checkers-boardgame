###############################################################################
# rules_driver.asm - standalone unit-test harness for rules.asm
#
# Reads integer commands from stdin (one per line) and invokes rules.asm
# routines directly on arbitrary injected board positions:
#   1            load board: next 8 lines, 8 chars each (_ 0 b r B R)
#   2 s d side   classify_move     -> prints "type err"
#   3 s d side   validate_move     -> prints "type err"
#   4 s d side   validate_chain    -> prints "type err"
#   5 s side     can_capture_from  -> prints 0/1
#   6 side       has_any_move      -> prints 0/1
#   7 s d        do_move           -> prints "promoted" then plain board
#   8 k v        set option k (1..9) = v
#   9 side       side_has_capture  -> prints 0/1
#  10 side       count_pieces      -> prints piece count
#   0            exit
# Run: java -jar Mars45.jar nc tests/unit/rules_driver.asm < commands.txt
###############################################################################
.include "../../src/defs.asm"

.data
turn:           .word 0
options:
opt_pretty:     .word 0
opt_rotate:     .word 0
opt_relnum:     .word 0
opt_detail:     .word 0
opt_hints:      .word 0
opt_forced:     .word 0
opt_flying:     .word 0
opt_bitmap:     .word 0
opt_replay:     .word 0
.text
.globl main
main:
    jal  init_board
driver_loop:
    jal  read_number
    beq  $v0, 1, cmd_load
    beq  $v0, 2, cmd_classify
    beq  $v0, 3, cmd_validate
    beq  $v0, 4, cmd_chain
    beq  $v0, 5, cmd_can_capture
    beq  $v0, 6, cmd_has_move
    beq  $v0, 7, cmd_do_move
    beq  $v0, 8, cmd_option
    beq  $v0, 9, cmd_side_capture
    beq  $v0, 10, cmd_count
    li   $v0, 10
    syscall

cmd_load:
    li   $s0, 0                 # row
cmd_load_row:
    jal  read_input_line
    bne  $v0, 8, driver_bad_row
    li   $s1, 0                 # col
cmd_load_col:
    lbu  $t0, input_line($s1)
    sll  $t1, $s0, 3
    add  $t1, $t1, $s1
    sb   $t0, board($t1)
    addi $s1, $s1, 1
    blt  $s1, 8, cmd_load_col
    addi $s0, $s0, 1
    blt  $s0, 8, cmd_load_row
    j    driver_loop

driver_bad_row:
    li   $a0, 1
    li   $v0, 17
    syscall

cmd_classify:
    jal  read_three
    jal  classify_move
    j    print_pair
cmd_validate:
    jal  read_three
    jal  validate_move
    j    print_pair
cmd_chain:
    jal  read_three
    jal  validate_chain
    j    print_pair

cmd_can_capture:
    jal  read_number
    move $s0, $v0
    jal  read_number
    move $a0, $s0
    move $a1, $v0
    jal  can_capture_from
    j    print_one
cmd_has_move:
    jal  read_number
    move $a0, $v0
    jal  has_any_move
    j    print_one
cmd_side_capture:
    jal  read_number
    move $a0, $v0
    jal  side_has_capture
    j    print_one
cmd_count:
    jal  read_number
    move $a0, $v0
    jal  count_pieces
    j    print_one

cmd_do_move:
    jal  read_number
    move $s0, $v0
    jal  read_number
    move $a0, $s0
    move $a1, $v0
    jal  do_move
    print_int_reg($v0)
    print_char(10)
    li   $a0, 0
    jal  print_board_plain
    j    driver_loop

cmd_option:
    jal  read_number
    move $s0, $v0
    jal  read_number
    addi $t0, $s0, -1
    sll  $t0, $t0, 2
    sw   $v0, options($t0)
    j    driver_loop

# read_three: read 3 integers into $a0, $a1, $a2
read_three:
    push($ra)
    jal  read_number
    move $s0, $v0
    jal  read_number
    move $s1, $v0
    jal  read_number
    move $a2, $v0
    move $a0, $s0
    move $a1, $s1
    pop($ra)
    jr   $ra

print_pair:
    move $t0, $v1
    print_int_reg($v0)
    print_char(32)
    print_int_reg($t0)
    print_char(10)
    j    driver_loop
print_one:
    print_int_reg($v0)
    print_char(10)
    j    driver_loop

.include "../../src/board_io.asm"
.include "../../src/rules.asm"
