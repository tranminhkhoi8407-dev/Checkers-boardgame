# BTL

```
// Mở giao diện UI
java -jar Mars45.jar

// Xem lại các ván trong tests bằng giao diện đồ họa Python (đọc input.txt và expected.txt, chỉ cần tkinter)
python3 gui.py

// Chơi trên terminal, không dùng UI
java -jar Mars45.jar nc src/main.asm
g++ -o main src/main.cpp && ./main

// Chạy lại một ván có sẵn
java -jar Mars45.jar nc src/main.asm < tests/test_001/input.txt
g++ -o main src/main.cpp && ./main < tests/test_001/input.txt

// Test python all test
pytest -v  tests/test_c.py
pytest -v  tests/test_mips.py
pytest -v  tests/

// Output thật được ghi vào tests/test_xxx/output_c.txt và output_mips.txt, khi sai sẽ in diff với expected.txt
```


---

<p align="center">
  <a href="https://www.facebook.com/Shiba.Tutor">
    <img src="https://img.shields.io/badge/Page%20Shiba.Tutor-0057FF?style=for-the-badge&logo=facebook&logoColor=white" alt="Facebook Page"/>
  </a>
  <a href="https://www.tiktok.com/@shiba.vo.tien">
    <img src="https://img.shields.io/badge/TikTok-000000?style=for-the-badge&logo=tiktok&logoColor=white" alt="TikTok"/>
  </a>
  <a href="https://www.facebook.com/groups/khmt.ktmt.cse.bku?locale=vi_VN">
    <img src="https://img.shields.io/badge/Facebook%20Group-4267B2?style=for-the-badge&logo=facebook&logoColor=white" alt="Facebook Group"/>
  </a>
  <a href="https://github.com/ShibaTutor">
    <img src="https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub"/>
  </a>
</p>
