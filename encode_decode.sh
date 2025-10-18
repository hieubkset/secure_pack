#!/bin/bash
#
# ============================================================
#  Script: encode_decode.sh
#  Tác giả: Trung Hieu Hoang
#  Mục đích:
#    - Mã hóa hoặc giải mã một chuỗi ký tự (ví dụ: tên) 
#      thành dạng có thể dùng làm tên thư mục hoặc tệp tin.
#
#  Cách dùng:
#    ./encode_decode.sh encode "<chuoi_goc>"
#      → Mã hóa chuỗi thành dạng an toàn cho tên thư mục.
#
#    ./encode_decode.sh decode "<chuoi_da_ma_hoa>"
#      → Giải mã chuỗi đã mã hóa về dạng gốc.
#
#  Ví dụ:
#    ./encode_decode.sh encode "Nguyen Van A"
#      => Tmd1eWVuIFZhbiBB
#
#    ./encode_decode.sh decode "Tmd1eWVuIFZhbiBB"
#      => Nguyen Van A
#
#  Ghi chú:
#    - Chuỗi mã hóa chỉ chứa ký tự [A-Za-z0-9_-], 
#      nên an toàn để đặt tên thư mục, file.
#    - Có thể giải mã ngược lại chính xác.
# ============================================================

if [ $# -ne 2 ]; then
  echo "Cách dùng:"
  echo "  $0 encode <ten_can_ma_hoa>"
  echo "  $0 decode <ten_da_ma_hoa>"
  exit 1
fi

action=$1
text=$2

if [ "$action" == "encode" ]; then
  # Mã hóa rồi thay ký tự để hợp lệ trong tên file/thư mục
  encoded=$(echo -n "$text" | base64 | tr '+/' '-_' | tr -d '=')
  echo "Kết quả mã hóa (hợp lệ làm tên thư mục): $encoded"

elif [ "$action" == "decode" ]; then
  # Phục hồi padding và ký tự gốc trước khi giải mã
  fixed=$(echo -n "$text" | sed 's/-/+/g; s/_/\//g')
  # Thêm padding lại nếu cần
  while [ $((${#fixed} % 4)) -ne 0 ]; do fixed="${fixed}="; done
  decoded=$(echo -n "$fixed" | base64 --decode)
  echo "Kết quả giải mã: $decoded"

else
  echo "Tham số không hợp lệ! Hãy dùng 'encode' hoặc 'decode'."
  exit 1
fi
