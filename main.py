"""Giao diện xem lại các ván Checkers trong thư mục tests.

File này không chứa luật chơi và không chạy MARS: bàn cờ lấy từ expected.txt, nước đi
lấy từ input.txt (mỗi dòng trả lời một lần chương trình hỏi ô).

Chạy: python3 main.py
"""
import re
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import messagebox, ttk

ROOT = Path(__file__).resolve().parent
TESTS_DIR = ROOT / "tests"
INPUT_FILE = "input.txt"
EXPECTED_FILE = "expected.txt"

N = 8
CELL = 72
PIECE_MARGIN = 11
KING_MARGIN = 25
AUTOPLAY_DELAY_MS = 700

LIGHT_SQUARE = "#f4f1ea"
DARK_SQUARE = "#64788a"
SELECTED_SQUARE = "#e0a526"
NUMBER_COLOR = "#dbe3ea"
PIECE_COLORS = {"b": "#17181a", "r": "#e02b20"}
KING_COLOR = "#e6c063"

STATUS_FONT = ("TkDefaultFont", 16, "bold")

SIDE_NAMES = {"Black": "Đen", "Red": "Đỏ"}

# Mỗi thông điệp của chương trình ứng với một sự kiện.
MESSAGES = [
    (re.compile(r"(Black|Red)'s turn\.\n"), "turn"),
    (re.compile(r"Enter starting square: "), "ask_start"),
    (re.compile(r"Enter landing square: "), "ask_landing"),
    (re.compile(r"Not a valid move! Try again\.\n"), "invalid"),
    (re.compile(r"Captured (Black|Red)'s piece\.\n"), "captured"),
    (re.compile(r"Chaining possible\.\n"), "chaining"),
    (re.compile(r"(Black|Red) wins!\n"), "winner"),
    (re.compile(r"([_0rbRB](?: [_0rbRB]){7})\n"), "row"),
]


@dataclass
class Frame:
    """Một bước trong ván: dòng ở danh sách nước đi và trạng thái bàn cờ sau bước đó."""

    board: list
    label: str
    message: str
    squares: tuple = ()


def square_of(row, col):
    """Trả về số ô 1..32 tại (row, col), hoặc None nếu là ô không dùng."""
    if (row + col) % 2 == 0:
        return None
    return row * 4 + col // 2 + 1


def parse_events(text):
    """Tách nội dung expected.txt thành danh sách sự kiện (kind, giá trị)."""
    events = []
    position = 0
    while position < len(text):
        if text[position] == "\n":
            position += 1
            continue
        for pattern, kind in MESSAGES:
            match = pattern.match(text, position)
            if match:
                events.append((kind, match.group(1) if pattern.groups else None))
                position = match.end()
                break
        else:
            line = text.count("\n", 0, position) + 1
            raise ValueError(f"{EXPECTED_FILE}: không đọc được dòng {line}")
    return events


class ReplayBuilder:
    """Ghép sự kiện của expected.txt với các dòng của input.txt thành danh sách Frame."""

    def __init__(self, answers):
        self.answers = iter(answers)
        self.frames = []
        self.rows = []
        self.side = None
        self.start = None        # ô đi của nước đang xét
        self.landing = None      # ô đến của nước đang xét
        self.last_landing = None # ô đáp của nước vừa đi, là ô đi khi ăn dây
        self.separator = "-"

    def build(self, events):
        for kind, value in events:
            getattr(self, f"_on_{kind}")(value)
        if next(self.answers, None) is not None:
            raise ValueError(f"{INPUT_FILE} còn thừa dòng so với {EXPECTED_FILE}")
        if not self.frames:
            raise ValueError(f"{EXPECTED_FILE} không có bàn cờ nào")
        return self.frames

    def _read_answer(self):
        answer = next(self.answers, None)
        if answer is None:
            raise ValueError(f"{INPUT_FILE} thiếu dòng so với {EXPECTED_FILE}")
        return answer.strip()

    def _on_turn(self, side):
        self.side = side

    def _on_ask_start(self, _):
        self.start = self._read_answer()

    def _on_ask_landing(self, _):
        if self.start is None:
            self.start = self.last_landing
        self.landing = self._read_answer()

    def _on_invalid(self, _):
        move = f"{self.start}-{self.landing}"
        self.frames.append(Frame(
            self.frames[-1].board,
            f"{SIDE_NAMES[self.side]}: {move} (sai)",
            f"{SIDE_NAMES[self.side]} đi {move}: nước đi không hợp lệ.",
            (self.start, self.landing),
        ))
        self.start = None

    def _on_captured(self, _):
        self.separator = "x"

    def _on_chaining(self, _):
        self.frames[-1].message += " Còn ăn tiếp được."

    def _on_row(self, row):
        self.rows.append(row.replace(" ", ""))
        if len(self.rows) == N:
            self._on_board(self.rows)
            self.rows = []

    def _on_board(self, board):
        if not self.frames:
            self.frames.append(Frame(board, "Bàn cờ ban đầu", "Đen đi trước."))
            return

        move = f"{self.start}{self.separator}{self.landing}"
        verb = "ăn quân" if self.separator == "x" else "đi"
        self.frames.append(Frame(
            board,
            f"{SIDE_NAMES[self.side]}: {move}",
            f"{SIDE_NAMES[self.side]} {verb} {move}.",
            (self.start, self.landing),
        ))
        self.last_landing = self.landing
        self.start = None
        self.separator = "-"

    def _on_winner(self, side):
        text = f"{SIDE_NAMES[side]} thắng!"
        self.frames.append(Frame(self.frames[-1].board, text, text))


def load_replay(test_dir):
    """Đọc một thư mục test và trả về danh sách Frame của ván đó."""
    answers = (test_dir / INPUT_FILE).read_text().splitlines()
    events = parse_events((test_dir / EXPECTED_FILE).read_text())
    return ReplayBuilder(answers).build(events)


def find_tests():
    """Các thư mục trong tests có đủ input.txt và expected.txt, sắp theo tên."""
    return sorted(
        path for path in TESTS_DIR.iterdir()
        if (path / INPUT_FILE).is_file() and (path / EXPECTED_FILE).is_file()
    )


class ReplayApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Checkers - Xem lại ván")
        self.resizable(False, False)

        self.tests = {path.name: path for path in find_tests()}
        self.frames = []
        self.index = 0
        self.autoplay_job = None

        self._build_widgets()
        if self.tests:
            self.test_box.current(0)
            self.load_selected_test()
        else:
            self.status_label.config(text="Không có test")
            self.message_label.config(text=f"Không tìm thấy test nào trong {TESTS_DIR}")
            self._draw()

    def _build_widgets(self):
        self.canvas = tk.Canvas(self, width=N * CELL, height=N * CELL, highlightthickness=0)
        self.canvas.grid(row=0, column=0, padx=12, pady=12)

        side = tk.Frame(self)
        side.grid(row=0, column=1, padx=(0, 12), pady=12, sticky="ns")

        tk.Label(side, text="Test").pack(anchor="w")
        self.test_box = ttk.Combobox(side, values=list(self.tests), state="readonly")
        self.test_box.pack(fill="x", pady=(2, 8))
        self.test_box.bind("<<ComboboxSelected>>", lambda _: self.load_selected_test())

        self.status_label = tk.Label(side, font=STATUS_FONT, width=18, anchor="w")
        self.status_label.pack(anchor="w")
        self.message_label = tk.Label(side, width=30, height=3, anchor="nw", justify="left", wraplength=240)
        self.message_label.pack(anchor="w", pady=(4, 8))
        self.count_label = tk.Label(side, anchor="w")
        self.count_label.pack(anchor="w", pady=(0, 8))

        tk.Label(side, text="Nước đã đi").pack(anchor="w")
        self.history = tk.Listbox(side, height=12, exportselection=False)
        self.history.pack(fill="both", expand=True, pady=(2, 8))
        self.history.bind("<<ListboxSelect>>", self._on_history_select)

        controls = tk.Frame(side)
        controls.pack(fill="x", pady=(0, 4))
        steps = [("|<", lambda: self.go_to(0)), ("<", lambda: self.step(-1)),
                 (">", lambda: self.step(1)), (">|", lambda: self.go_to(len(self.frames) - 1))]
        for column, (text, command) in enumerate(steps):
            controls.columnconfigure(column, weight=1)
            button = tk.Button(controls, text=text, command=self._stopping(command))
            button.grid(row=0, column=column, sticky="ew")

        self.play_button = tk.Button(side, text="Tự chạy", command=self.toggle_autoplay)
        self.play_button.pack(fill="x")

        self.bind("<Left>", lambda _: self._stopping(lambda: self.step(-1))())
        self.bind("<Right>", lambda _: self._stopping(lambda: self.step(1))())

    # ---------- Điều khiển ----------
    def load_selected_test(self):
        self.stop_autoplay()
        name = self.test_box.get()
        try:
            self.frames = load_replay(self.tests[name])
        except (OSError, UnicodeDecodeError, ValueError) as error:
            self.frames = []
            self.history.delete(0, tk.END)
            self.status_label.config(text="Lỗi đọc test")
            self.message_label.config(text="")
            self.count_label.config(text="")
            self._draw()
            messagebox.showerror("Không đọc được test", f"{name}: {error}")
            return

        self.history.delete(0, tk.END)
        self.history.insert(tk.END, *(frame.label for frame in self.frames))
        self.go_to(0)

    def go_to(self, index):
        if not self.frames:
            return
        self.index = max(0, min(index, len(self.frames) - 1))
        frame = self.frames[self.index]

        self.status_label.config(text=f"Bước {self.index}/{len(self.frames) - 1}")
        self.message_label.config(text=frame.message)
        cells = "".join(frame.board).lower()
        self.count_label.config(text=f"Đen còn {cells.count('b')} quân  ·  Đỏ còn {cells.count('r')} quân")

        self.history.selection_clear(0, tk.END)
        self.history.selection_set(self.index)
        self.history.see(self.index)
        self._draw()

    def step(self, delta):
        self.go_to(self.index + delta)

    def _on_history_select(self, _):
        selection = self.history.curselection()
        if selection:
            self.stop_autoplay()
            self.go_to(selection[0])

    def _stopping(self, command):
        """Bọc một thao tác tay: người dùng tự bấm thì dừng chế độ tự chạy."""
        def run():
            self.stop_autoplay()
            command()
        return run

    def toggle_autoplay(self):
        if self.autoplay_job is not None:
            self.stop_autoplay()
            return
        if not self.frames:
            return
        if self.index == len(self.frames) - 1:
            self.go_to(0)
        self.play_button.config(text="Dừng")
        self.autoplay_job = self.after(AUTOPLAY_DELAY_MS, self._autoplay_tick)

    def _autoplay_tick(self):
        self.step(1)
        if self.index == len(self.frames) - 1:
            self.stop_autoplay()
        else:
            self.autoplay_job = self.after(AUTOPLAY_DELAY_MS, self._autoplay_tick)

    def stop_autoplay(self):
        if self.autoplay_job is not None:
            self.after_cancel(self.autoplay_job)
            self.autoplay_job = None
        self.play_button.config(text="Tự chạy")

    # ---------- Vẽ ----------
    def _draw(self):
        frame = self.frames[self.index] if self.frames else None
        self.canvas.delete("all")
        for row in range(N):
            for col in range(N):
                self._draw_cell(row, col, frame)

    def _draw_cell(self, row, col, frame):
        square = square_of(row, col)
        x, y = col * CELL, row * CELL

        color = LIGHT_SQUARE if square is None else DARK_SQUARE
        if frame and square is not None and str(square) in frame.squares:
            color = SELECTED_SQUARE
        self.canvas.create_rectangle(x, y, x + CELL, y + CELL, fill=color, outline="")

        if square is None:
            return
        self.canvas.create_text(x + 4, y + 3, text=str(square), anchor="nw", fill=NUMBER_COLOR, font=("TkDefaultFont", 8))

        piece = frame.board[row][col] if frame else "0"
        if piece == "0":
            return
        self.canvas.create_oval(
            x + PIECE_MARGIN, y + PIECE_MARGIN, x + CELL - PIECE_MARGIN, y + CELL - PIECE_MARGIN,
            fill=PIECE_COLORS[piece.lower()], outline="",
        )
        if piece.isupper():
            self.canvas.create_oval(
                x + KING_MARGIN, y + KING_MARGIN, x + CELL - KING_MARGIN, y + CELL - KING_MARGIN,
                fill=KING_COLOR, outline="",
            )


if __name__ == "__main__":
    ReplayApp().mainloop()
