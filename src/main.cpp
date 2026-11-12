#include <cstdlib>
#include <iostream>
#include <string>

/* ================= Cấu hình ================= */
constexpr int N = 8;
constexpr int SQUARES = 32;

constexpr char EMPTY = '0';

constexpr int NOBODY = -1;
constexpr int BLACK = 0;
constexpr int RED = 1;

constexpr int INVALID = 0;
constexpr int STEP = 1;
constexpr int CAPTURE = 2;

/* ================= Trạng thái game ================= */
char board[N][N + 1] = {
    "_r_r_r_r",
    "r_r_r_r_",
    "_r_r_r_r",
    "0_0_0_0_",
    "_0_0_0_0",
    "b_b_b_b_",
    "_b_b_b_b",
    "b_b_b_b_",
};

int turn = BLACK;

/* ================= Tiện ích ================= */
void printBoard()
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

bool hasAnyMove()
{
    // TODO CODE
}

void playTurn()
{
    std::cout << (turn == BLACK ? "Black's turn.\n" : "Red's turn.\n");

    // TODO CODE
}

int main()
{
    printBoard();

    // Bên tới lượt không còn nước đi (hết quân hoặc bị chặn) là thua.
    while (hasAnyMove())
    {
        playTurn();
        turn = 1 - turn;
    }

    std::cout << (turn == BLACK ? "Red wins!\n" : "Black wins!\n");
    return 0;
}
