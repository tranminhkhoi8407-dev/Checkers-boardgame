// Checkers (English variant) - C++ reference model for src/*.asm.
//
// Serves as executable pseudocode: each function here mirrors a MIPS procedure
// of the same name for side-by-side verification, debugging, and reporting.
// This C++ reference implements the mandatory core requirements matching
// tests/test_001..005; extra menu features (option 0) live exclusively in MIPS.
//
//   Board, I/O & Main Loop (Nguyen Thanh Hau): init_board, print_board,
//                                              read_number, play_turn, main
//   Game Rules Engine      (Tran Minh Khoi):   classify_move, can_capture_from,
//                                              can_step_from, has_any_move, do_move
#include <cstdlib>
#include <iostream>
#include <string>

/* ================= Configuration ================= */
constexpr int N = 8;
constexpr int SQUARES = 32;

constexpr char EMPTY = '0';
constexpr char UNUSED = '_';

constexpr int BLACK = 0;
constexpr int RED = 1;

constexpr int INVALID = 0;
constexpr int STEP = 1;
constexpr int CAPTURE = 2;

/* ================= Game State ================= */
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

/* ================= Board and I/O (Nguyen Thanh Hau) ================= */
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

// Square 1..32 -> (row, col). Even rows place dark squares on odd cols; odd rows on even cols.
void square_to_rc(int s, int &r, int &c)
{
    r = (s - 1) / 4;
    c = 2 * ((s - 1) % 4) + (r % 2 == 0 ? 1 : 0);
}

// Read one line and parse as non-negative integer. Returns -1 on invalid input
// (letters, empty lines, trailing garbage, etc.); exits cleanly on EOF.
int read_number()
{
    std::string line;
    if (!std::getline(std::cin, line))
        std::exit(0); // end of input
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

/* ================= Rules Engine (Tran Minh Khoi) ================= */
bool on_board(int r, int c) { return r >= 0 && r < N && c >= 0 && c < N; }
bool is_own(char p, int side) { return side == BLACK ? (p == 'b' || p == 'B') : (p == 'r' || p == 'R'); }
bool is_enemy(char p, int side) { return is_own(p, 1 - side); }
bool is_king(char p) { return p == 'B' || p == 'R'; }
int forward_dir(int side) { return side == BLACK ? -1 : 1; }

// Check whether piece p can move in row direction dr (kings move both ways).
bool dir_allowed(char p, int side, int dr) { return is_king(p) || dr == forward_dir(side); }

// Classify move s -> d for side: INVALID, STEP, or CAPTURE.
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

// Active side loses if eliminated or completely blocked with no legal move.
bool has_any_move()
{
    for (int r = 0; r < N; ++r)
        for (int c = 0; c < N; ++c)
            if (is_own(board[r][c], turn) && (can_capture_from(r, c, turn) || can_step_from(r, c, turn)))
                return true;
    return false;
}

// Apply a validated move, remove captured enemy piece, and promote on back rank.
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

/* ================= Turn Controller (Nguyen Thanh Hau) ================= */
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

    // Capture move: enforce mandatory chain captures with the same piece.
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
