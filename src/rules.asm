###############################################################################
# rules.asm - GAME RULES ENGINE (Owner: Tran Minh Khoi)
#
# Move validation, normal steps, captures, king promotion, mandatory chain
# captures, forced first capture, and flying kings variant. Included by
# main.asm (not assembled standalone).
#
# Calling convention (standard MIPS32 ABI):
#   - Arguments in $a0..$a3; return value in $v0 (and $v1 when applicable).
#   - Callee must preserve $s0..$s7, $sp, and $ra.
#   - $t*, $a*, and $v* are caller-saved.
#
# Numbering: canonical squares 1..32 (Black at the bottom). Board stored in
# 64-byte array "board" (board_io.asm) at index r*8 + c.
#   Black (side 0): pawn 'b', king 'B', moves upward (dr=-1), crowns at row 0.
#   Red   (side 1): pawn 'r', king 'R', moves downward (dr=+1), crowns at row 7.
#
# Return codes for classify_move / validate_move / validate_chain:
#   $v0 = INVALID (0) | STEP (1) | CAPTURE (2)
#   $v1 = ERR_* error code when $v0 = INVALID (see defs.asm and err_table in board_io.asm)
###############################################################################

.text

# -----------------------------------------------------------------------------
# is_own(a0 = piece char, a1 = side) -> v0 = 1 if piece belongs to side, else 0
# -----------------------------------------------------------------------------
is_own:
    li   $v0, 1
    bnez $a1, is_own_red
    beq  $a0, 'b', is_own_done
    beq  $a0, 'B', is_own_done
    li   $v0, 0
    jr   $ra
is_own_red:
    beq  $a0, 'r', is_own_done
    beq  $a0, 'R', is_own_done
    li   $v0, 0
is_own_done:
    jr   $ra

# -----------------------------------------------------------------------------
# is_enemy(a0 = piece char, a1 = side) -> v0 = 1 if opponent's piece, else 0
# (empty, unused, and out-of-bounds cells all return 0)
# -----------------------------------------------------------------------------
is_enemy:
    xori $a1, $a1, 1            # flip side and tail-call is_own
    j    is_own

# -----------------------------------------------------------------------------
# is_king(a0 = piece char) -> v0 = 1 if king ('B' or 'R'), else 0
# -----------------------------------------------------------------------------
is_king:
    li   $v0, 1
    beq  $a0, KING_BLACK, is_king_done
    beq  $a0, KING_RED, is_king_done
    li   $v0, 0
is_king_done:
    jr   $ra

# -----------------------------------------------------------------------------
# dir_allowed(a0 = piece char, a1 = side, a2 = row delta sign dr in {-1, +1})
#   -> v0 = 1 if the piece may travel in row direction dr.
# Kings move both ways; pawns move forward only (Black: -1, Red: +1).
# -----------------------------------------------------------------------------
dir_allowed:
    li   $v0, 1
    beq  $a0, KING_BLACK, dir_allowed_done
    beq  $a0, KING_RED, dir_allowed_done
    li   $t0, -1                # Black forward direction
    beqz $a1, dir_allowed_cmp
    li   $t0, 1                 # Red forward direction
dir_allowed_cmp:
    seq  $v0, $a2, $t0
dir_allowed_done:
    jr   $ra

# -----------------------------------------------------------------------------
# check_start(a0 = starting square, a1 = side) -> v0 = 0 if valid, else ERR_*
#   ERR_RANGE (outside 1..32), ERR_EMPTY (empty), ERR_NOT_YOURS (enemy piece)
# -----------------------------------------------------------------------------
check_start:
    push($ra)
    push($s0)
    move $s0, $a1               # s0 = side
    li   $v0, ERR_RANGE
    blt  $a0, 1, check_start_ret
    bgt  $a0, 32, check_start_ret
    jal  square_piece           # v0 = cell char at square a0
    move $a0, $v0
    li   $v0, ERR_EMPTY
    beq  $a0, EMPTY, check_start_ret
    move $a1, $s0
    jal  is_own
    move $t0, $v0
    li   $v0, 0
    bnez $t0, check_start_ret
    li   $v0, ERR_NOT_YOURS     # piece belongs to opponent
check_start_ret:
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# classify_move(a0 = start s, a1 = dest d, a2 = side) -> v0 = type, v1 = err
#
# Checks pure move geometry (independent of global forced-capture rule):
#   1. Valid starting square occupied by side's piece (check_start)
#   2. Landing square in 1..32 and currently empty
#   3. Diagonal alignment and allowed direction
#   4. Standard pawn/king: 1 square = STEP, 2 squares over enemy = CAPTURE
#      Flying king (when opt_flying=1): arbitrary clear diagonal step, or jump
#      over exactly one enemy piece onto any empty square behind it.
# -----------------------------------------------------------------------------
classify_move:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    push($s5)
    push($s6)
    push($s7)
    move $s0, $a2               # s0 = side
    move $s1, $a0               # s1 = s (temp)
    move $s2, $a1               # s2 = d (temp)

    # 1. Starting square
    move $a1, $s0
    jal  check_start
    move $v1, $v0
    bnez $v1, classify_invalid

    # 2. Landing square
    li   $v1, ERR_RANGE
    blt  $s2, 1, classify_invalid
    bgt  $s2, 32, classify_invalid
    move $a0, $s2
    jal  sq_to_rc
    move $s5, $v0               # s5 = rd
    move $s6, $v1               # s6 = cd
    move $a0, $v0
    move $a1, $s6
    jal  get_cell
    li   $v1, ERR_OCCUPIED
    bne  $v0, EMPTY, classify_invalid

    # 3. Diagonal geometry and movement direction
    move $a0, $s1
    jal  sq_to_rc
    move $s1, $v0               # s1 = rs
    move $s2, $v1               # s2 = cs
    sub  $t0, $s5, $s1          # dr = rd - rs
    sub  $t1, $s6, $s2          # dc = cd - cs
    abs  $t2, $t0
    abs  $t3, $t1
    li   $v1, ERR_NOT_DIAGONAL
    bne  $t2, $t3, classify_invalid
    move $s5, $t2               # s5 = n = diagonal distance
    li   $s3, 1                 # s3 = sdr = sign(dr)
    bgtz $t0, classify_sdc
    li   $s3, -1
classify_sdc:
    li   $s4, 1                 # s4 = sdc = sign(dc)
    bgtz $t1, classify_dir
    li   $s4, -1
classify_dir:
    move $a0, $s1
    move $a1, $s2
    jal  get_cell
    move $s6, $v0               # s6 = moving piece char
    move $a0, $s6
    move $a1, $s0
    move $a2, $s3
    jal  dir_allowed
    li   $v1, ERR_BACKWARD
    beqz $v0, classify_invalid

    # 4. Distance and intermediate-square checks
    lw   $t0, opt_flying
    beqz $t0, classify_short
    move $a0, $s6
    jal  is_king
    bnez $v0, classify_flying

classify_short:                 # English rules: 1 = STEP, 2 over enemy = CAPTURE
    li   $v0, STEP
    li   $v1, 0
    beq  $s5, 1, classify_ret
    li   $v1, ERR_TOO_FAR
    bne  $s5, 2, classify_invalid
    add  $a0, $s1, $s3          # midpoint cell
    add  $a1, $s2, $s4
    jal  get_cell
    move $a0, $v0
    move $a1, $s0
    jal  is_enemy
    li   $v1, ERR_NO_ENEMY
    beqz $v0, classify_invalid
    li   $v0, CAPTURE
    li   $v1, 0
    j    classify_ret

classify_flying:                # flying king: scan all cells between s and d
    li   $s6, 1                 # s6 = k (step index along diagonal)
    li   $s7, 0                 # s7 = enemy count encountered on path
classify_fly_loop:
    bge  $s6, $s5, classify_fly_end
    mul  $t0, $s6, $s3
    add  $a0, $s1, $t0
    mul  $t1, $s6, $s4
    add  $a1, $s2, $t1
    jal  get_cell
    addi $s6, $s6, 1
    beq  $v0, EMPTY, classify_fly_loop
    move $a0, $v0
    move $a1, $s0
    jal  is_enemy
    li   $v1, ERR_BLOCKED
    beqz $v0, classify_invalid  # blocked by friendly piece
    addi $s7, $s7, 1
    bgt  $s7, 1, classify_invalid   # cannot jump over two enemies at once
    j    classify_fly_loop
classify_fly_end:
    li   $v0, STEP
    li   $v1, 0
    beqz $s7, classify_ret
    li   $v0, CAPTURE
    j    classify_ret

classify_invalid:
    li   $v0, INVALID
classify_ret:
    pop($s7)
    pop($s6)
    pop($s5)
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# validate_move(a0 = s, a1 = d, a2 = side) -> v0 = type, v1 = err
# Wraps classify_move and enforces mandatory first capture when opt_forced = 1.
# -----------------------------------------------------------------------------
validate_move:
    push($ra)
    push($s0)
    move $s0, $a2
    jal  classify_move
    bne  $v0, STEP, validate_move_ret
    lw   $t0, opt_forced
    beqz $t0, validate_move_ret
    move $a0, $s0
    jal  side_has_capture
    li   $v1, 0
    move $t0, $v0
    li   $v0, STEP
    beqz $t0, validate_move_ret
    li   $v0, INVALID
    li   $v1, ERR_MUST_CAPTURE
validate_move_ret:
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# validate_chain(a0 = locked square, a1 = d, a2 = side) -> v0, v1
# During a capture chain, only captures by the same locked piece are accepted.
# -----------------------------------------------------------------------------
validate_chain:
    push($ra)
    jal  classify_move
    bne  $v0, STEP, validate_chain_ret
    li   $v0, INVALID
    li   $v1, ERR_CHAIN
validate_chain_ret:
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# can_capture_from(a0 = square, a1 = side) -> v0 = 1 if piece can capture
# Used for chain capture detection, forced capture, and win/blockade detection.
# -----------------------------------------------------------------------------
can_capture_from:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    push($s5)
    push($s6)
    push($s7)
    move $s0, $a1               # s0 = side
    jal  sq_to_rc
    move $s1, $v0               # s1 = r
    move $s2, $v1               # s2 = c
    move $a0, $v0
    move $a1, $v1
    jal  get_cell
    move $s3, $v0               # s3 = piece char
    li   $s4, 0                 # s4 = direction index i (0..3)
can_capture_dir:
    bge  $s4, 4, can_capture_no
    andi $t0, $s4, 2            # i = 0,1: dr = -1 ; i = 2,3: dr = +1
    li   $s5, -1
    beqz $t0, can_capture_dc
    li   $s5, 1
can_capture_dc:
    andi $t0, $s4, 1            # even i: dc = -1 ; odd i: dc = +1
    li   $s6, -1
    beqz $t0, can_capture_check
    li   $s6, 1
can_capture_check:
    addi $s4, $s4, 1
    move $a0, $s3
    move $a1, $s0
    move $a2, $s5
    jal  dir_allowed
    beqz $v0, can_capture_dir
    li   $s7, 1                 # s7 = k: distance along diagonal
    lw   $t0, opt_flying
    beqz $t0, can_capture_try
    move $a0, $s3
    jal  is_king
    beqz $v0, can_capture_try
can_capture_skip:               # flying king: skip leading empty squares
    mul  $t0, $s7, $s5
    add  $a0, $s1, $t0
    mul  $t1, $s7, $s6
    add  $a1, $s2, $t1
    jal  get_cell
    bne  $v0, EMPTY, can_capture_try
    addi $s7, $s7, 1
    j    can_capture_skip
can_capture_try:                # square k must be enemy, square k+1 must be empty
    mul  $t0, $s7, $s5
    add  $a0, $s1, $t0
    mul  $t1, $s7, $s6
    add  $a1, $s2, $t1
    jal  get_cell
    move $a0, $v0
    move $a1, $s0
    jal  is_enemy
    beqz $v0, can_capture_dir
    addi $s7, $s7, 1
    mul  $t0, $s7, $s5
    add  $a0, $s1, $t0
    mul  $t1, $s7, $s6
    add  $a1, $s2, $t1
    jal  get_cell
    bne  $v0, EMPTY, can_capture_dir
    li   $v0, 1
    j    can_capture_ret
can_capture_no:
    li   $v0, 0
can_capture_ret:
    pop($s7)
    pop($s6)
    pop($s5)
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# can_step_from(a0 = square, a1 = side) -> v0 = 1 if piece has a legal step
# (checks adjacent empty diagonal squares in allowed directions)
# -----------------------------------------------------------------------------
can_step_from:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    push($s4)
    push($s5)
    push($s6)
    move $s0, $a1               # s0 = side
    jal  sq_to_rc
    move $s1, $v0               # s1 = r
    move $s2, $v1               # s2 = c
    move $a0, $v0
    move $a1, $v1
    jal  get_cell
    move $s3, $v0               # s3 = piece char
    li   $s4, 0                 # s4 = direction index i (0..3)
can_step_dir:
    bge  $s4, 4, can_step_no
    andi $t0, $s4, 2            # i = 0,1: dr = -1 ; i = 2,3: dr = +1
    li   $s5, -1
    beqz $t0, can_step_dc
    li   $s5, 1
can_step_dc:
    andi $t0, $s4, 1            # even i: dc = -1 ; odd i: dc = +1
    li   $s6, -1
    beqz $t0, can_step_check
    li   $s6, 1
can_step_check:
    addi $s4, $s4, 1
    move $a0, $s3
    move $a1, $s0
    move $a2, $s5
    jal  dir_allowed
    beqz $v0, can_step_dir
    add  $a0, $s1, $s5
    add  $a1, $s2, $s6
    jal  get_cell
    bne  $v0, EMPTY, can_step_dir
    li   $v0, 1
    j    can_step_ret
can_step_no:
    li   $v0, 0
can_step_ret:
    pop($s6)
    pop($s5)
    pop($s4)
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# has_any_move(a0 = side) -> v0 = 1 if side has at least one legal move.
# Returns 0 if eliminated or completely blocked (side loses).
# -----------------------------------------------------------------------------
has_any_move:
    push($ra)
    push($s0)
    push($s1)
    move $s0, $a0               # s0 = side
    li   $s1, 1                 # s1 = current square
has_any_move_loop:
    bgt  $s1, 32, has_any_move_no
    move $a0, $s1
    jal  square_piece
    move $a0, $v0
    move $a1, $s0
    jal  is_own
    beqz $v0, has_any_move_next
    move $a0, $s1
    move $a1, $s0
    jal  can_step_from
    bnez $v0, has_any_move_ret
    move $a0, $s1
    move $a1, $s0
    jal  can_capture_from
    bnez $v0, has_any_move_ret
has_any_move_next:
    addi $s1, $s1, 1
    j    has_any_move_loop
has_any_move_no:
    li   $v0, 0
has_any_move_ret:
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# side_has_capture(a0 = side) -> v0 = 1 if side has at least one capture move
# -----------------------------------------------------------------------------
side_has_capture:
    push($ra)
    push($s0)
    push($s1)
    move $s0, $a0
    li   $s1, 1
side_has_capture_loop:
    bgt  $s1, 32, side_has_capture_no
    move $a0, $s1
    jal  square_piece
    move $a0, $v0
    move $a1, $s0
    jal  is_own
    beqz $v0, side_has_capture_next
    move $a0, $s1
    move $a1, $s0
    jal  can_capture_from
    bnez $v0, side_has_capture_ret
side_has_capture_next:
    addi $s1, $s1, 1
    j    side_has_capture_loop
side_has_capture_no:
    li   $v0, 0
side_has_capture_ret:
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# do_move(a0 = s, a1 = d) -> v0 = 1 if piece was promoted to king
# Executes an already-validated move: relocates piece, clears any intermediate
# captured enemy along the diagonal, and crowns pawns reaching row 0 or row 7.
# -----------------------------------------------------------------------------
do_move:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a1               # save d
    jal  sq_to_rc
    move $s1, $v0               # s1 = rs
    move $s2, $v1               # s2 = cs
    move $a0, $s0
    jal  sq_to_rc               # v0 = rd, v1 = cd
    sll  $t0, $s1, 3
    add  $t0, $t0, $s2          # t0 = start index
    sll  $t1, $v0, 3
    add  $t1, $t1, $v1          # t1 = dest index
    lbu  $s3, board($t0)        # s3 = moving piece
    sb   $s3, board($t1)
    li   $t2, EMPTY
    sb   $t2, board($t0)

    # Clear intermediate diagonal cells (removes jumped enemy for short & flying)
    sub  $t3, $v0, $s1
    sub  $t4, $v1, $s2
    li   $t5, 8                 # flat-array diagonal stride: sdr*8 + sdc
    bgtz $t3, do_move_dc
    li   $t5, -8
do_move_dc:
    addi $t5, $t5, 1
    bgtz $t4, do_move_clear
    addi $t5, $t5, -2
do_move_clear:
    add  $t0, $t0, $t5
    beq  $t0, $t1, do_move_promote
    sb   $t2, board($t0)
    j    do_move_clear

    # Instant king promotion upon landing on the final row
do_move_promote:
    li   $t6, 0                 # t6 = promoted flag
    bne  $s3, PAWN_BLACK, do_move_red
    bnez $v0, do_move_ret
    li   $t7, KING_BLACK
    sb   $t7, board($t1)
    li   $t6, 1
    j    do_move_ret
do_move_red:
    bne  $s3, PAWN_RED, do_move_ret
    bne  $v0, 7, do_move_ret
    li   $t7, KING_RED
    sb   $t7, board($t1)
    li   $t6, 1
do_move_ret:
    move $v0, $t6
    pop($s3)
    pop($s2)
    pop($s1)
    pop($s0)
    pop($ra)
    jr   $ra
