# Checkers boardgame — CO2008

## Chạy trên MARS 4.5

Chạy lệnh sau ở thư mục dự án để chơi trên terminal.

```powershell
java -jar Mars45.jar nc src/main.asm
```

Để chơi trong giao diện MARS, chạy `java -jar Mars45.jar`, mở `src/main.asm`, bấm **F3** để assemble rồi **F5** để chạy. Phần nhập và xuất nằm trong tab **Run I/O**. Trong **Settings**, tắt **Assemble all files in directory** và **Delayed branching**. Khi sao chép source, giữ cả bốn file `.asm` cùng nhau trong `src/`. `main.asm` ghép `defs.asm`, `board_io.asm` và `rules.asm` bằng `.include`.

## Cách chơi

- Đen đi trước. Nhập một số từ `1` đến `32` cho ô xuất phát, sau đó nhập ô đích. Khi mở game, bàn cờ hiển thị số ô, số quân hai bên và hai luật đang áp dụng. Ô `1` là ô chơi đầu tiên trên hàng trên cùng, còn ô `29` ở góc dưới trái.
- `b` và `r` là quân thường, `B` và `R` là vua. Bàn cờ có khung dùng dấu `.` cho ô chơi trống. Bàn cờ gọn dùng `0` cho ô chơi trống và `_` cho ô sáng.
- Nhập `0` tại **Enter starting square** để mở menu. Chọn `1` để đổi kiểu bàn cờ, `2` để xoay bàn vào lượt Đỏ với số ô chuẩn hoặc `3` để Đỏ có bàn xoay và cách đánh số ô riêng. Chọn `4` để giải thích lỗi, `5` để gợi ý nước đi, `9` để hỏi chơi lại, `12` để bắt đầu ván mới hoặc `13` để thoát. Chọn `14` để bật đồng thời các tùy chọn tiện ích `1–5` và `9`. Chọn `0` trong menu để tiếp tục ván.
- Nước sai giữ nguyên lượt. Khi được ăn tiếp, bảng chỉ rõ số ô của quân đang phải đi và chỉ hỏi ô đích tiếp theo. Quân vừa phong vua có thể ăn ngược ngay trong chuỗi. Tùy chọn `6` bật bắt buộc ăn ngay từ đầu lượt. Tùy chọn `7` bật vua bay.
- **Bitmap Display** (menu `8`) vẽ quân xanh đậm và đỏ trên nền kem và xanh lục xám, với vương miện vàng cho vua. Trong **Tools → Bitmap Display**, chọn **Unit Width** và **Unit Height** là `8`, **Display Width** và **Display Height** là `512`, **Base address** là `0x10040000 (heap)`, rồi bấm **Connect to MIPS**. Điều khiển nước đi và cài đặt qua **Run I/O**.

## Chạy và đối chiếu kiểm thử

```powershell
Get-Content tests/test_001/input.txt | java -jar Mars45.jar nc src/main.asm pa classic
python -m pytest -v tests/test_mips.py tests/test_features.py tests/test_rules.py
```

Các kiểm thử MIPS cần Java và `pytest`. Tham số MARS `pa classic` khởi động với bàn cờ gọn để đối chiếu đúng transcript mẫu. Chạy `python -m pytest -v tests/` để kiểm tra thêm bản C++ tham chiếu nếu có `g++`. Năm ván trong `tests/test_001` đến `tests/test_005` có sẵn `input.txt` và `expected.txt`. Khi chạy, test ghi kết quả vào `output_mips.txt` hoặc `output_c.txt` để đối chiếu. Có thể mở `python gui.py` để xem lại ván mẫu bằng Tkinter.

| Mục bàn giao                                  | Kiểm thử                                                                                                                                                                                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Khởi tạo đúng 12 quân mỗi bên và Đen đi trước | `test_initial_board_and_black_moves_first` kiểm tra đủ 64 ô và lượt đầu.                                                                                                                                                                                                  |
| Nhập sai và hết đầu vào                       | `test_bad_input_does_not_crash` thử chữ, dòng rỗng, số ngoài phạm vi và dòng quá dài, rồi thực hiện nước hợp lệ. Các test đầu vào còn kiểm tra EOF và CRLF.                                                                                                               |
| Nước sai không mất lượt                       | `test_invalid_move_does_not_lose_turn` thử nước sai hình học, quân đối phương và ô xuất phát trống trước khi Đen đi hợp lệ.                                                                                                                                               |
| Đổi lượt đúng và khóa quân trong chuỗi ăn     | `test_turns_alternate_after_each_valid_move` và `test_promotion_chain_keeps_turn_and_locks_piece`. Ván mẫu 001 có chuỗi `11x2 2x9 9x18`. Đen phong vua ở ô `2`, ăn ngược ngay và chỉ chuyển lượt sau khi đến ô `18`.                                                      |
| Thông báo đúng người thắng                    | `test_mips_games` đối chiếu toàn bộ kết quả của năm ván. Ván 001, 002 và 005 kết thúc khi bên thua hết quân. Ván 003 và 004 kết thúc khi bên thua còn quân nhưng hết nước đi.                                                                                             |
| Luật phong vua theo Hình 8 trong đề           | `test_promotion_by_capture_then_chain_backward` dựng thế cờ `15x24 24x31 31x22 22x13` và kiểm tra bàn cờ sau các bước.                                                                                                                                                    |
| Tính nhất quán giữa hiển thị và nhập liệu     | `test_numbered_board_agrees_with_red_input` thử cả bật xoay riêng và để tùy chọn số ô của Đỏ tự xoay. `test_pretty_chain_identifies_the_piece_in_red_numbering` đối chiếu số ô hiện trong chuỗi ăn.                                                                       |
| Gợi ý, bắt buộc ăn và vua bay                 | `test_flying_king_capture_is_required_and_hinted` đưa Đỏ đến thế có vua ở `32`, kiểm tra gợi ý `14`, từ chối `32-27` và kiểm tra bàn cờ sau `32x14`.                                                                                                                      |
| Giao diện và chơi lại                         | `test_default_board_explains_controls_and_current_rules` kiểm tra bàn cờ mở màn. `test_bitmap_display_memory` kiểm tra màu nền, quân và vương miện trong bộ nhớ MARS. `test_pretty_board_reports_elimination_and_restarts_after_win` kiểm tra chơi lại sau một ván thắng. |

## Demo luật nâng cao trên MARS

Mở ván mới với cách đánh số chuẩn. Nhập từng số trên một dòng. Với chuỗi ăn, nhập ô xuất phát một lần rồi lần lượt nhập các ô đích.

| Giai đoạn           | Nước đi hoặc thao tác                  | Quan sát                                                                                 |
| ------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------- |
| Chuẩn bị thế cờ     | `23-19 9-14 27-23 6-9 32-27 2-6 23-18` | Đến lượt Đỏ.                                                                             |
| Phong vua           | `14x23 23x32`, rồi Đen đi `22-18`      | Đỏ phong vua ở `32`. Đen đặt một quân ở `18`, cách vua ba ô chéo.                        |
| Bật luật và gợi ý   | `0 → 4 → 5 → 6 → 7 → 0`                | Bảng luật hiện **Flying** và **Required**. Hệ thống gợi ý chọn vua ở `32` và đáp ở `14`. |
| Từ chối nước thường | `32-27`                                | Báo phải ăn quân. Vẫn lượt Đỏ.                                                           |
| Ăn xa               | `32x14`                                | Vua Đỏ tới `14`, quân Đen ở `18` biến mất và lượt chuyển sang Đen.                       |

Để demo giao diện theo lượt, mở ván mới và bật mục `3`. Sau khi Đen đi `21-17`, Đỏ thấy ô `29` ở góc dưới trái. Nhập `24-20` theo số đang hiển thị để thực hiện nước `9-13` theo số chuẩn. Bật mục `8` nếu đã kết nối Bitmap Display để trình diễn cùng lúc hai cách hiển thị.

Khi giải thích phần Assembly, dùng chuỗi `11x2 2x9 9x18` của ván mẫu 001. `sq_to_rc` đổi số ô thành hàng và cột của mảng 64 byte. `play_turn` gọi `validate_move` với ô xuất phát, ô đích và bên đang đi trong `$a0–$a2`. `do_move` cập nhật bàn cờ và phong vua trước khi `can_capture_from` đọc lại quân ở ô vừa đáp. Nhờ thứ tự đó, vua mới ở ô `2` có thể ăn ngược tới ô `9` ngay trong cùng lượt.
