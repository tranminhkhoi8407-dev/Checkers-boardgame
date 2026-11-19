// Checkers (English variant) - bản C++ tham chiếu cho src/*.asm.
//
// File này dùng làm "mã giả chạy được": mỗi hàm ở đây ứng với một hàm cùng tên
// trong bản MIPS, để dễ đối chiếu, debug và viết báo cáo. Bản C++ chỉ làm phần
// bắt buộc của đề (đúng output của tests/); các tính năng mở rộng (menu 0) chỉ có
// trong bản MIPS.
//
//   Phần của Hậu (board_io.asm, main.asm): init_board, print_board, read_number,
//                                          play_turn, main
//   Phần của Khôi (rules.asm):             classify_move, can_capture_from,
//                                          can_step_from, has_any_move, do_move
#include <cstdlib>
#include <iostream>
#include <string>

/* ================= Cấu hình ================= */
constexpr int N = 8;
constexpr int SQUARES = 32;

constexpr char EMPTY = '0';
constexpr char UNUSED = '_';

constexpr int BLACK = 0;
constexpr int RED = 1;

constexpr int INVALID = 0;
constexpr int STEP = 1;
constexpr int CAPTURE = 2;

/* ================= Trạng thái game ================= */
const char *const START_BOARD[N] = {
    "_r_r_r_r",
    "r_r_r_r_",
    "_r_r_r_r",
    "0_0_0_0_",
    "_0_0_0_0",
    "b_b_b_b_",
    "_b_b_b_b",
    "b_b_b_b_",
};

char board[N][N + 1];
int turn = BLACK;

/* ================= Bàn cờ và nhập/xuất (Hậu) ================= */
void init_board()
{
    for (int i = 0; i < N; ++i)
        for (int j = 0; j <= N; ++j)
            board[i][j] = START_BOARD[i][j];
    turn = BLACK;
}

void print_board()
{
    for (int i = 0; i < N; ++i)
    {
        for (int j = 0; j < N; ++j)
        {
            std::cout << board[i][j];
            if (j + 1 < N)
                std::cout << ' ';
        }
        std::cout << '\n';
    }
}

// Ô 1..32 -> (hàng, cột). Hàng chẵn: ô tối ở cột lẻ; hàng lẻ: ô tối ở cột chẵn.
void square_to_rc(int s, int &r, int &c)
{
    r = (s - 1) / 4;
    c = 2 * ((s - 1) % 4) + (r % 2 == 0 ? 1 : 0);
}

// Đọc một dòng và đổi sang số. Trả về -1 nếu dòng không phải một số nguyên dương
// (chữ, để trống, có ký tự lạ...). Không bao giờ làm chương trình dừng.
int read_number()
{
    std::string line;
    if (!std::getline(std::cin, line))
        std::exit(0); // hết input
    std::size_t i = 0;
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t'))
        ++i;
    int value = 0, digits = 0;
    while (i < line.size() && line[i] >= '0' && line[i] <= '9')
    {
        if (value < 1000)
            value = value * 10 + (line[i] - '0');
        ++digits, ++i;
    }
    while (i < line.size() && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r'))
        ++i;
    if (digits == 0 || i != line.size())
        return -1;
    return value;
}

/* ================= Luật chơi (Khôi) ================= */
bool on_board(int r, int c) { return r >= 0 && r < N && c >= 0 && c < N; }
bool is_own(char p, int side) { return side == BLACK ? (p == 'b' || p == 'B') : (p == 'r' || p == 'R'); }
bool is_enemy(char p, int side) { return is_own(p, 1 - side); }
bool is_king(char p) { return p == 'B' || p == 'R'; }
int forward_dir(int side) { return side == BLACK ? -1 : 1; }

// Quân ở (r, c) có được đi theo hướng hàng dr không? Vua đi được cả hai hướng.
bool dir_allowed(char p, int side, int dr) { return is_king(p) || dr == forward_dir(side); }

// Phân loại nước s -> d của bên side: INVALID, STEP hoặc CAPTURE.
int classify_move(int s, int d, int side)
{
    if (s < 1 || s > SQUARES || d < 1 || d > SQUARES)
        return INVALID;
    int rs, cs, rd, cd;
    square_to_rc(s, rs, cs);
    square_to_rc(d, rd, cd);
    char p = board[rs][cs];
    if (!is_own(p, side) || board[rd][cd] != EMPTY)
        return INVALID;
    int dr = rd - rs, dc = cd - cs;
    if (std::abs(dr) != std::abs(dc))
        return INVALID;
    if (!dir_allowed(p, side, dr > 0 ? 1 : -1))
        return INVALID;
    if (std::abs(dr) == 1)
        return STEP;
    if (std::abs(dr) == 2 && is_enemy(board[rs + dr / 2][cs + dc / 2], side))
        return CAPTURE;
    return INVALID;
}

bool can_capture_from(int r, int c, int side)
{
    char p = board[r][c];
    for (int dr = -1; dr <= 1; dr += 2)
        for (int dc = -1; dc <= 1; dc += 2)
            if (dir_allowed(p, side, dr) && on_board(r + 2 * dr, c + 2 * dc) &&
                is_enemy(board[r + dr][c + dc], side) && board[r + 2 * dr][c + 2 * dc] == EMPTY)
                return true;
    return false;
}

bool can_step_from(int r, int c, int side)
{
    char p = board[r][c];
    for (int dr = -1; dr <= 1; dr += 2)
        for (int dc = -1; dc <= 1; dc += 2)
            if (dir_allowed(p, side, dr) && on_board(r + dr, c + dc) && board[r + dr][c + dc] == EMPTY)
                return true;
    return false;
}

// Bên tới lượt không còn nước đi (hết quân hoặc bị chặn) là thua.
bool has_any_move()
{
    for (int r = 0; r < N; ++r)
        for (int c = 0; c < N; ++c)
            if (is_own(board[r][c], turn) && (can_capture_from(r, c, turn) || can_step_from(r, c, turn)))
                return true;
    return false;
}

// Thực hiện nước đi đã hợp lệ, xóa quân bị ăn và phong vua khi tới hàng cuối.
void do_move(int s, int d, int type)
{
    int rs, cs, rd, cd;
    square_to_rc(s, rs, cs);
    square_to_rc(d, rd, cd);
    board[rd][cd] = board[rs][cs];
    board[rs][cs] = EMPTY;
    if (type == CAPTURE)
        board[(rs + rd) / 2][(cs + cd) / 2] = EMPTY;
    if (board[rd][cd] == 'b' && rd == 0)
        board[rd][cd] = 'B';
    if (board[rd][cd] == 'r' && rd == N - 1)
        board[rd][cd] = 'R';
}

/* ================= Điều khiển lượt chơi (Hậu) ================= */
void play_turn()
{
    std::cout << (turn == BLACK ? "Black's turn.\n" : "Red's turn.\n");

    int s, d, type;
    while (true)
    {
        std::cout << "Enter starting square: ";
        s = read_number();
        std::cout << "Enter landing square: ";
        d = read_number();
        type = classify_move(s, d, turn);
        if (type != INVALID)
            break;
        std::cout << "Not a valid move! Try again.\n";
    }

    do_move(s, d, type);
    if (type == STEP)
    {
        print_board();
        return;
    }

    // Ăn quân, rồi bắt buộc ăn liên hoàn bằng chính quân vừa ăn.
    while (true)
    {
        std::cout << (turn == BLACK ? "Captured Red's piece.\n" : "Captured Black's piece.\n");
        print_board();
        int r, c;
        square_to_rc(d, r, c);
        if (!can_capture_from(r, c, turn))
            return;
        std::cout << "Chaining possible.\n";
        s = d;
        while (true)
        {
            std::cout << "Enter landing square: ";
            d = read_number();
            if (classify_move(s, d, turn) == CAPTURE)
                break;
            std::cout << "Not a valid move! Try again.\n";
        }
        do_move(s, d, CAPTURE);
    }
}

int main()
{
    init_board();
    print_board();

    while (has_any_move())
    {
        play_turn();
        turn = 1 - turn;
    }

    std::cout << (turn == BLACK ? "Red wins!\n" : "Black wins!\n");
    return 0;
}
