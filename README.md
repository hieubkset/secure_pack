# 🔐 Secure Pack

**Secure Pack** là một shell script giúp bạn dễ dàng **nén**, **mã hóa**, **chia nhỏ** các file hoặc thư mục lớn để sao lưu, và **khôi phục** lại đúng nguyên trạng ban đầu.  
Tất cả đều gói gọn trong một file duy nhất — tiện lợi, an toàn và dễ sử dụng.

---

## 🚀 Tính năng

### 1️⃣ Chế độ **Pack**
- Chấp nhận đầu vào là **thư mục** hoặc **file**.
- Nếu là thư mục → tự động **nén thành `.tar`**.
- Cho phép **mã hóa tùy chọn** (AES-256 qua `gpg`) với mật khẩu do người dùng cung cấp.
- Cho phép **chỉ định kích thước tối đa** của từng phần nhỏ (đơn vị MB, mặc định 1024 MB).
- Cho phép chỉ định **thư mục chứa kết quả**.
- Tự động tạo file **manifest** lưu thông tin cần thiết để khôi phục chính xác (bao gồm loại dữ liệu, tên gốc, thời gian, v.v.).
- Hỗ trợ tạo **checksum SHA-256** cho từng phần (nếu hệ thống có `sha256sum`).

### 2️⃣ Chế độ **Restore**
- Cho phép chỉ định **thư mục đầu vào** (chứa các file nhỏ).
- Cho phép chỉ định **thư mục đầu ra**.
- Cho phép nhập **mật khẩu** để giải mã (nếu đã mã hóa khi pack).
- Tự động **ghép các file nhỏ** thành một khối duy nhất.
- Tự nhận biết và **giải mã nếu có mã hóa**.
- Tự động **giải nén nếu là `.tar`**.
- Khôi phục **đúng loại dữ liệu ban đầu**:
  - Nếu gốc là thư mục → xuất ra thư mục.
  - Nếu gốc là file → xuất ra file gốc.

---

## ⚙️ Cài đặt

1. Lưu script này dưới tên `secure_pack.sh`
2. Cấp quyền thực thi:
```bash
   chmod +x secure_pack.sh
````

3. Cài đặt các công cụ cần thiết:

```bash
   sudo apt install tar gpg coreutils
```

   (`sha256sum` và `file` thường có sẵn trong Ubuntu/Debian)

---

## 🧩 Cách sử dụng

### 🎁 PACK – Nén / Mã hóa / Chia nhỏ

```bash
./secure_pack.sh pack [-s SIZE_MB] [-o OUT_DIR] [-p PASSWORD] <PATH>
```

**Tham số:**

| Tham số       | Ý nghĩa                         | Mặc định             |
| ------------- | ------------------------------- | -------------------- |
| `-s SIZE_MB`  | Dung lượng tối đa mỗi phần (MB) | `1024`               |
| `-o OUT_DIR`  | Thư mục lưu kết quả             | Cùng nơi với đầu vào |
| `-p PASSWORD` | Mật khẩu để mã hóa bằng GPG     | Không mã hóa         |
| `<PATH>`      | Đường dẫn tới file hoặc thư mục | Bắt buộc             |

**Ví dụ:**

```bash
# Chia nhỏ thư mục 2GB/phần và mã hóa bằng mật khẩu
./secure_pack.sh pack -s 2048 -o /backup -p "m@tkh@u" /data/my_project

# Chia nhỏ một file lớn 1GB/phần, không mã hóa
./secure_pack.sh pack /data/large_video.mp4
```

---

### ♻️ RESTORE – Ghép / Giải mã / Giải nén

```bash
./secure_pack.sh restore -i INPUT_DIR [-d DEST_DIR] [-p PASSWORD]
```

**Tham số:**

| Tham số        | Ý nghĩa                               | Mặc định                   |
| -------------- | ------------------------------------- | -------------------------- |
| `-i INPUT_DIR` | Thư mục chứa các file part & manifest | Bắt buộc                   |
| `-d DEST_DIR`  | Thư mục khôi phục                     | `INPUT_DIR/restore_out`    |
| `-p PASSWORD`  | Mật khẩu để giải mã (nếu có mã hóa)   | Không cần nếu không mã hóa |

**Ví dụ:**

```bash
# Khôi phục dữ liệu đã mã hóa
./secure_pack.sh restore -i /backup -d /restore_here -p "m@tkh@u"

# Khôi phục dữ liệu không mã hóa
./secure_pack.sh restore -i /backup -d /restore_here
```

---

## 📦 Cấu trúc file sau khi PACK

Sau khi chạy `pack`, bạn sẽ có cấu trúc tương tự như:

```
backup/
├── my_project_20251007_120501_part_0000
├── my_project_20251007_120501_part_0001
├── my_project_20251007_120501_part_0002
├── my_project_20251007_120501_manifest.txt
└── my_project_20251007_120501_part_checksums.sha256
```

File `manifest.txt` chứa thông tin cần thiết để khôi phục đúng kiểu dữ liệu (thư mục/file gốc).

---

## 🔒 Bảo mật

* Mã hóa bằng **GPG AES-256** ở chế độ đối xứng (`--symmetric`).
* Mật khẩu không lưu trong file hay manifest.
* Bạn có thể bỏ qua bước mã hóa bằng cách không cung cấp `-p`.

> ⚠️ **Cảnh báo:**
> Khi truyền mật khẩu qua dòng lệnh (`-p "m@tkh@u"`), có thể thấy trong lịch sử shell (`history`) hoặc lệnh `ps`.
> Để an toàn hơn, bạn có thể sửa script để đọc mật khẩu bằng lệnh `read -s` (ẩn nhập từ bàn phím).

---

## 🧰 Phụ thuộc

* `bash` ≥ 4.0
* `tar`
* `split`
* `gpg` (nếu dùng mã hóa)
* `sha256sum` *(tùy chọn, để tạo checksum)*
* `file`, `awk`, `readlink`

