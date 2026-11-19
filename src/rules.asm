###############################################################################
# rules.asm - LUẬT CHƠI (phần phụ trách: Khôi)
#
# Kiểm tra nước đi, đi thường, ăn quân, phong vua, ăn liên hoàn, bắt buộc ăn
# và biến thể vua bay. File này được .include từ main.asm, không chạy riêng.
#
# Quy ước gọi hàm (chuẩn MIPS):
#   - Tham số $a0..$a3, kết quả $v0 (và $v1 nếu có).
#   - Hàm được gọi phải giữ nguyên $s0..$s7, $sp, $ra của hàm gọi.
#   - $t*, $a*, $v* có thể bị thay đổi sau mỗi lần gọi hàm.
#
# Cách đánh số: ô 1..32 theo ký hiệu chuẩn (phía Đen ở dưới). Bàn cờ lưu trong
# mảng 64 byte "board" (board_io.asm), phần tử board[r*8 + c].
#   Đen  (side 0): quân 'b', vua 'B', đi lên (hàng giảm), phong vua ở hàng 0.
#   Đỏ   (side 1): quân 'r', vua 'R', đi xuống (hàng tăng), phong vua ở hàng 7.
#
# Mã kết quả của classify_move / validate_move / validate_chain:
#   $v0 = INVALID (0) | STEP (1) | CAPTURE (2)
#   $v1 = mã lỗi ERR_* khi $v0 = INVALID (xem main.asm và err_table)
###############################################################################

.text

# -----------------------------------------------------------------------------
# is_own(a0 = ký tự quân, a1 = side) -> v0 = 1 nếu quân thuộc về side, ngược lại 0
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
# is_enemy(a0 = ký tự quân, a1 = side) -> v0 = 1 nếu là quân của đối phương
# (ô trống, ô không dùng hay ngoài bàn đều trả về 0)
# -----------------------------------------------------------------------------
is_enemy:
    xori $a1, $a1, 1            # đổi sang bên kia rồi dùng lại is_own
    j    is_own

# -----------------------------------------------------------------------------
# is_king(a0 = ký tự quân) -> v0 = 1 nếu là vua ('B' hoặc 'R')
# -----------------------------------------------------------------------------
is_king:
    li   $v0, 1
    beq  $a0, KING_BLACK, is_king_done
    beq  $a0, KING_RED, is_king_done
    li   $v0, 0
is_king_done:
    jr   $ra

# -----------------------------------------------------------------------------
# dir_allowed(a0 = ký tự quân, a1 = side, a2 = hướng hàng dr (+1/-1))
#   -> v0 = 1 nếu quân được đi theo hướng đó.
# Vua đi cả hai hướng; quân thường chỉ đi tới (Đen: -1, Đỏ: +1).
# -----------------------------------------------------------------------------
dir_allowed:
    li   $v0, 1
    beq  $a0, KING_BLACK, dir_allowed_done
    beq  $a0, KING_RED, dir_allowed_done
    li   $t0, -1                # hướng tiến của Đen
    beqz $a1, dir_allowed_cmp
    li   $t0, 1                 # hướng tiến của Đỏ
dir_allowed_cmp:
    seq  $v0, $a2, $t0
dir_allowed_done:
    jr   $ra

# -----------------------------------------------------------------------------
# check_start(a0 = ô xuất phát, a1 = side) -> v0 = 0 nếu hợp lệ, ngược lại mã lỗi
#   ERR_RANGE (ô ngoài 1..32), ERR_EMPTY (ô trống), ERR_NOT_YOURS (quân đối phương)
# -----------------------------------------------------------------------------
check_start:
    push($ra)
    push($s0)
    move $s0, $a1               # s0 = side
    li   $v0, ERR_RANGE
    blt  $a0, 1, check_start_ret
    bgt  $a0, 32, check_start_ret
    jal  square_piece           # v0 = ký tự quân tại ô a0
    move $a0, $v0
    li   $v0, ERR_EMPTY
    beq  $a0, EMPTY, check_start_ret
    move $a1, $s0
    jal  is_own
    move $t0, $v0
    li   $v0, 0
    bnez $t0, check_start_ret
    li   $v0, ERR_NOT_YOURS     # không phải quân của mình
check_start_ret:
    pop($s0)
    pop($ra)
    jr   $ra

# -----------------------------------------------------------------------------
# classify_move(a0 = ô đi s, a1 = ô đến d, a2 = side) -> v0 = loại nước, v1 = lỗi
#
# Chỉ xét hình học của một bước (chưa xét luật bắt buộc ăn):
#   1. ô đi hợp lệ và là quân của side         (check_start)
#   2. ô đến trong 1..32 và đang trống
#   3. đi đúng đường chéo, đúng hướng
#   4. quân thường / vua thường: 1 ô = đi, 2 ô qua quân địch = ăn
#      vua bay (khi bật): đi xa tùy ý trên đường chéo trống, hoặc nhảy qua
#      đúng một quân địch rồi đáp xuống ô trống phía sau.
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
    move $s1, $a0               # s1 = s (tạm)
    move $s2, $a1               # s2 = d (tạm)

    # 1. Ô xuất phát
    move $a1, $s0
    jal  check_start
    move $v1, $v0
    bnez $v1, classify_invalid

    # 2. Ô đích
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

    # 3. Đường chéo và hướng đi
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
    move $s5, $t2               # s5 = n = số ô phải vượt qua
    li   $s3, 1                 # s3 = sdr = dấu của dr
    bgtz $t0, classify_sdc
    li   $s3, -1
classify_sdc:
    li   $s4, 1                 # s4 = sdc = dấu của dc
    bgtz $t1, classify_dir
    li   $s4, -1
classify_dir:
    move $a0, $s1
    move $a1, $s2
    jal  get_cell
    move $s6, $v0               # s6 = ký tự quân đang đi
    move $a0, $s6
    move $a1, $s0
    move $a2, $s3
    jal  dir_allowed
    li   $v1, ERR_BACKWARD
    beqz $v0, classify_invalid

    # 4. Khoảng cách
    lw   $t0, opt_flying
    beqz $t0, classify_short
    move $a0, $s6
    jal  is_king
    bnez $v0, classify_flying

classify_short:                 # luật Anh: 1 ô = đi, 2 ô = ăn
    li   $v0, STEP
    li   $v1, 0
    beq  $s5, 1, classify_ret
    li   $v1, ERR_TOO_FAR
    bne  $s5, 2, classify_invalid
    add  $a0, $s1, $s3          # ô ở giữa
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

classify_flying:                # vua bay: duyệt các ô nằm giữa s và d
    li   $s6, 1                 # s6 = k (ô thứ k trên đường đi)
    li   $s7, 0                 # s7 = số quân địch gặp trên đường
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
    beqz $v0, classify_invalid  # quân mình chắn đường
    addi $s7, $s7, 1
    bgt  $s7, 1, classify_invalid   # không được nhảy qua 2 quân
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
# validate_move(a0 = s, a1 = d, a2 = side) -> v0 = loại nước, v1 = lỗi
# Như classify_move, cộng thêm luật bắt buộc ăn (khi opt_forced bật):
# nếu bên đi có nước ăn thì không được đi thường.
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
# validate_chain(a0 = ô quân vừa ăn, a1 = d, a2 = side) -> v0, v1
# Trong chuỗi ăn liên hoàn chỉ chấp nhận nước ăn bằng chính quân vừa ăn.
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
# can_capture_from(a0 = ô, a1 = side) -> v0 = 1 nếu quân ở ô đó còn ăn được
# Dùng để phát hiện ăn liên hoàn, bắt buộc ăn và kiểm tra còn nước đi.
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
    move $s3, $v0               # s3 = ký tự quân
    li   $s4, 0                 # s4 = hướng thứ i (0..3)
can_capture_dir:
    bge  $s4, 4, can_capture_no
    andi $t0, $s4, 2            # i = 0,1: dr = -1 ; i = 2,3: dr = +1
    li   $s5, -1
    beqz $t0, can_capture_dc
    li   $s5, 1
can_capture_dc:
    andi $t0, $s4, 1            # i chẵn: dc = -1 ; i lẻ: dc = +1
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
    li   $s7, 1                 # s7 = k: ô cách quân k bước
    lw   $t0, opt_flying
    beqz $t0, can_capture_try
    move $a0, $s3
    jal  is_king
    beqz $v0, can_capture_try
can_capture_skip:               # vua bay: bỏ qua các ô trống phía trước
    mul  $t0, $s7, $s5
    add  $a0, $s1, $t0
    mul  $t1, $s7, $s6
    add  $a1, $s2, $t1
    jal  get_cell
    bne  $v0, EMPTY, can_capture_try
    addi $s7, $s7, 1
    j    can_capture_skip
can_capture_try:                # ô thứ k phải là quân địch, ô k+1 phải trống
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
# can_step_from(a0 = ô, a1 = side) -> v0 = 1 nếu quân ở ô đó đi thường được
# (có ô chéo kề bên, đúng hướng, đang trống)
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
    move $s3, $v0               # s3 = ký tự quân
    li   $s4, 0                 # s4 = hướng thứ i (0..3)
can_step_dir:
    bge  $s4, 4, can_step_no
    andi $t0, $s4, 2            # i = 0,1: dr = -1 ; i = 2,3: dr = +1
    li   $s5, -1
    beqz $t0, can_step_dc
    li   $s5, 1
can_step_dc:
    andi $t0, $s4, 1            # i chẵn: dc = -1 ; i lẻ: dc = +1
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
# has_any_move(a0 = side) -> v0 = 1 nếu bên đó còn ít nhất một nước đi.
# Hết quân hoặc mọi quân đều bị chặn -> 0 (bên đó thua).
# -----------------------------------------------------------------------------
has_any_move:
    push($ra)
    push($s0)
    push($s1)
    move $s0, $a0               # s0 = side
    li   $s1, 1                 # s1 = ô đang xét
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
# side_has_capture(a0 = side) -> v0 = 1 nếu bên đó có ít nhất một nước ăn
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
# do_move(a0 = s, a1 = d) -> v0 = 1 nếu quân vừa được phong vua
# Thực hiện nước đi ĐÃ được kiểm tra hợp lệ: chuyển quân, xóa mọi quân nằm
# giữa s và d (chính là quân bị ăn, nếu có) và phong vua khi tới hàng cuối.
# -----------------------------------------------------------------------------
do_move:
    push($ra)
    push($s0)
    push($s1)
    push($s2)
    push($s3)
    move $s0, $a1               # giữ d
    jal  sq_to_rc
    move $s1, $v0               # s1 = rs
    move $s2, $v1               # s2 = cs
    move $a0, $s0
    jal  sq_to_rc               # v0 = rd, v1 = cd
    sll  $t0, $s1, 3
    add  $t0, $t0, $s2          # t0 = chỉ số ô đi
    sll  $t1, $v0, 3
    add  $t1, $t1, $v1          # t1 = chỉ số ô đến
    lbu  $s3, board($t0)        # s3 = quân đang đi
    sb   $s3, board($t1)
    li   $t2, EMPTY
    sb   $t2, board($t0)

    # Xóa các ô nằm giữa (quân bị ăn)
    sub  $t3, $v0, $s1
    sub  $t4, $v1, $s2
    li   $t5, 8                 # bước chỉ số theo hướng: dr*8 + dc
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

    # Phong vua
do_move_promote:
    li   $t6, 0                 # t6 = đã phong vua?
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
