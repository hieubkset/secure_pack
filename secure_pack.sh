#!/usr/bin/env bash
# secure_pack.sh
# Chức năng:
#   - pack:   nén (nếu là thư mục), mã hóa (tùy chọn), chia nhỏ theo MB, tạo manifest
#   - restore: ghép, giải mã (nếu có), và khôi phục đúng kiểu đầu vào (dir/file)
#
# Yêu cầu công cụ: tar, split, gpg (nếu dùng mã hóa), sha256sum (không bắt buộc), file, awk

set -euo pipefail
shopt -s nullglob
export LC_ALL=C

# ---------- Utils ----------
err() { echo "Lỗi: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Cần lệnh '$1'."; exit 1; }; }

usage() {
  cat <<'USAGE'
Cách dùng:

  1) PACK (nén/mã hóa/chia nhỏ):
     secure_pack.sh pack [-s SIZE_MB] [-o OUT_DIR] [-p PASSWORD] <PATH>
       -s SIZE_MB    Kích thước tối đa mỗi phần (MB). Mặc định: 1024
       -o OUT_DIR    Thư mục chứa kết quả (mặc định: cùng nơi với PATH)
       -p PASSWORD   Mật khẩu mã hóa (GPG AES-256). Nếu bỏ qua -> không mã hóa

  2) RESTORE (ghép/giải mã/giải nén):
     secure_pack.sh restore -i INPUT_DIR [-d DEST_DIR] [-p PASSWORD]
       -i INPUT_DIR  Thư mục chứa các file part & manifest
       -d DEST_DIR   Thư mục đích (mặc định: INPUT_DIR/restore_out)
       -p PASSWORD   Mật khẩu giải mã (bắt buộc nếu đã mã hóa khi pack)

Ví dụ:
  secure_pack.sh pack -s 2048 -o /backups -p "m@tkh@u" /data/myfolder
  secure_pack.sh restore -i /backups -d /restore_here -p "m@tkh@u"
USAGE
}

ts_now() { date +%Y%m%d_%H%M%S; }

write_manifest() {
  # $1: manifest_path
  # Tham số đọc từ biến môi trường:
  #   ORIGIN_TYPE, ORIGIN_NAME, ORIGIN_BASENAME, TIMESTAMP, ENCRYPTED (0/1), SIZE_MB, PART_PREFIX
  cat > "$1" <<EOF
# Manifest for secure_pack.sh
ORIGIN_TYPE=$ORIGIN_TYPE
ORIGIN_NAME=$ORIGIN_NAME
ORIGIN_BASENAME=$ORIGIN_BASENAME
TIMESTAMP=$TIMESTAMP
ENCRYPTED=$ENCRYPTED
SIZE_MB=$SIZE_MB
PART_PREFIX=$PART_PREFIX
EOF
}

read_manifest() {
  # $1: manifest_path
  # export biến vào môi trường hiện tại
  local m="$1"
  [[ -f "$m" ]] || { err "Không tìm thấy manifest: $m"; exit 1; }
  # shellcheck disable=SC1090
  set -a
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^#|^$ ]] && continue
    case "$k" in
      ORIGIN_TYPE|ORIGIN_NAME|ORIGIN_BASENAME|TIMESTAMP|ENCRYPTED|SIZE_MB|PART_PREFIX)
        eval "$k=\"\$v\""
        ;;
    esac
  done < <(grep -E '^(ORIGIN_TYPE|ORIGIN_NAME|ORIGIN_BASENAME|TIMESTAMP|ENCRYPTED|SIZE_MB|PART_PREFIX)=' "$m")
  set +a
}

human_list_parts() {
  local prefix="$1"
  for f in "${prefix}"[0-9][0-9][0-9][0-9]; do
    ls -lh "$f" | sed 's/^/  /'
  done
}

detect_is_tar() {
  # $1: filepath
  tar -tf "$1" >/dev/null 2>&1
}

detect_is_gpg() {
  # $1: filepath
  if file -b "$1" 2>/dev/null | grep -qiE 'pgp|gpg|openpgp'; then
    return 0
  fi
  if command -v gpg >/dev/null 2>&1 && gpg --batch --list-packets "$1" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ---------- Subcommand: pack ----------
cmd_pack() {
  need tar; need split; need readlink; need dirname; need basename

  local SIZE_MB=1024 OUT_DIR="" PASSWORD=""
  while getopts ":s:o:p:h" opt; do
    case "$opt" in
      s) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || { err "SIZE_MB phải là số nguyên dương."; exit 1; }; SIZE_MB="$OPTARG" ;;
      o) OUT_DIR="$OPTARG" ;;
      p) PASSWORD="$OPTARG" ;;
      h) usage; exit 0 ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))
  [[ $# -ge 1 ]] || { err "Thiếu PATH."; usage; exit 1; }

  local INPUT_PATH="$1"
  [[ -e "$INPUT_PATH" ]] || { err "Không tồn tại: $INPUT_PATH"; exit 1; }

  local INPUT_ABS INPUT_DIR ORIGIN_NAME ORIGIN_BASENAME ORIGIN_TYPE TIMESTAMP
  INPUT_ABS="$(readlink -f "$INPUT_PATH")"
  INPUT_DIR="$(dirname "$INPUT_ABS")"
  ORIGIN_NAME="$(basename "$INPUT_ABS")"
  ORIGIN_BASENAME="$ORIGIN_NAME"
  TIMESTAMP="$(ts_now)"

  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="$INPUT_DIR"
  fi
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(readlink -f "$OUT_DIR")"

  # Xác định loại đầu vào
  if [[ -d "$INPUT_ABS" ]]; then
    ORIGIN_TYPE="dir"
  elif [[ -f "$INPUT_ABS" ]]; then
    ORIGIN_TYPE="file"
  else
    err "PATH không phải file/thư mục hợp lệ."
    exit 1
  fi

  # 1) Chuẩn bị khối (nếu dir -> tar; nếu file -> dùng trực tiếp)
  local WORK_FILE CREATED_TAR=0
  if [[ "$ORIGIN_TYPE" == "dir" ]]; then
    WORK_FILE="$OUT_DIR/${ORIGIN_BASENAME}_${TIMESTAMP}.tar"
    echo "→ Nén thư mục thành TAR: $WORK_FILE"
    tar -C "$(dirname "$INPUT_ABS")" -cf "$WORK_FILE" "$(basename "$INPUT_ABS")"
    CREATED_TAR=1
  else
    WORK_FILE="$INPUT_ABS"
    echo "→ Sử dụng file đầu vào: $WORK_FILE"
  fi

  # 2) (Tùy chọn) Mã hóa
  local ENCRYPTED=0 BLOB_FILE="$WORK_FILE" CREATED_GPG=0
  if [[ -n "$PASSWORD" ]]; then
    need gpg
    BLOB_FILE="$OUT_DIR/$(basename "$WORK_FILE").gpg"
    echo "→ Mã hóa bằng GPG (AES-256)…"
    gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "$PASSWORD" -o "$BLOB_FILE" "$WORK_FILE"
    ENCRYPTED=1
  fi

  # 3) Chia nhỏ
  local SIZE_BYTES=$(( SIZE_MB * 1024 * 1024 ))
  local PART_PREFIX="$OUT_DIR/${ORIGIN_BASENAME}_${TIMESTAMP}_part_"
  echo "→ Chia file: ${BLOB_FILE} -> ${SIZE_MB}MB/phần"
  split -b "$SIZE_BYTES" -d -a 4 -- "$BLOB_FILE" "$PART_PREFIX"

  # 4) Manifest
  local MANIFEST="${OUT_DIR}/${ORIGIN_BASENAME}_${TIMESTAMP}_manifest.txt"
  write_manifest "$MANIFEST"
  echo "→ Đã tạo manifest: $MANIFEST"

  # 5) (Tùy chọn) Checksum (không bắt buộc)
  if command -v sha256sum >/dev/null 2>&1; then
    local CHECK_FILE="${PART_PREFIX}checksums.sha256"
    echo "→ Tạo checksum…"
    sha256sum "${PART_PREFIX}"[0-9][0-9][0-9][0-9] > "$CHECK_FILE"
  fi

  # 6) Dọn dẹp tạm
  if [[ "$ENCRYPTED" -eq 1 ]]; then rm -f -- "$BLOB_FILE"; fi
  if [[ "$CREATED_TAR" -eq 1 ]]; then rm -f -- "$WORK_FILE"; fi

  echo "✅ PACK hoàn tất. Các phần:"
  human_list_parts "$PART_PREFIX"
  echo "Manifest: $MANIFEST"
}

# ---------- Subcommand: restore ----------
cmd_restore() {
  need readlink; need awk; need file

  local INPUT_DIR="" DEST_DIR="" PASSWORD=""
  while getopts ":i:d:p:h" opt; do
    case "$opt" in
      i) INPUT_DIR="$OPTARG" ;;
      d) DEST_DIR="$OPTARG" ;;
      p) PASSWORD="$OPTARG" ;;
      h) usage; exit 0 ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -n "$INPUT_DIR" ]] || { err "Cần -i INPUT_DIR."; usage; exit 1; }
  INPUT_DIR="$(readlink -f "$INPUT_DIR")"
  [[ -d "$INPUT_DIR" ]] || { err "Không tìm thấy thư mục: $INPUT_DIR"; exit 1; }

  # Tìm manifest mới nhất
  local MANIFEST
  MANIFEST="$(ls -1t "$INPUT_DIR"/*_manifest.txt 2>/dev/null | head -n1 || true)"
  [[ -n "$MANIFEST" ]] || { err "Không tìm thấy manifest trong $INPUT_DIR"; exit 1; }

  # Đọc manifest
  local ORIGIN_TYPE ORIGIN_NAME ORIGIN_BASENAME TIMESTAMP ENCRYPTED SIZE_MB PART_PREFIX
  read_manifest "$MANIFEST"

  [[ -n "${PART_PREFIX:-}" ]] || { err "Manifest thiếu PART_PREFIX."; exit 1; }

  echo "→ Khôi phục theo manifest:"
  echo "   ORIGIN_TYPE = $ORIGIN_TYPE"
  echo "   ORIGIN_NAME = $ORIGIN_NAME"
  echo "   ENCRYPTED   = $ENCRYPTED"
  echo "   PART_PREFIX = $PART_PREFIX"

  # Kiểm tra đủ parts
  local PART0="${PART_PREFIX}0000"
  [[ -f "$PART0" ]] || { err "Thiếu part đầu tiên: $PART0"; exit 1; }

  # (Tùy chọn) kiểm checksum
  local CHECK_FILE="${PART_PREFIX}checksums.sha256"
  if [[ -f "$CHECK_FILE" ]] && command -v sha256sum >/dev/null 2>&1; then
    echo "→ Kiểm tra checksum…"
    (cd "$INPUT_DIR" && sha256sum -c "$(basename "$CHECK_FILE")")
    echo "→ Checksum OK."
  fi

  # Ghép parts
  local MERGED_FILE="$INPUT_DIR/${ORIGIN_BASENAME}_${TIMESTAMP}.merged"
  echo "→ Ghép parts -> $MERGED_FILE"
  cat "${PART_PREFIX}"[0-9][0-9][0-9][0-9] > "$MERGED_FILE"

  # Giải mã nếu cần
  local PAYLOAD_FILE="$MERGED_FILE"
  if [[ "${ENCRYPTED:-0}" -eq 1 ]]; then
    need gpg
    [[ -n "$PASSWORD" ]] || { err "Bộ dữ liệu đã mã hóa. Cần -p PASSWORD để giải mã."; exit 1; }
    local DECRYPTED="${MERGED_FILE}.decrypted"
    echo "→ Giải mã bằng GPG…"
    gpg --batch --yes --passphrase "$PASSWORD" -o "$DECRYPTED" -d "$MERGED_FILE"
    rm -f -- "$MERGED_FILE"
    PAYLOAD_FILE="$DECRYPTED"
  fi

  # Đích khôi phục
  if [[ -z "$DEST_DIR" ]]; then
    DEST_DIR="$INPUT_DIR/restore_out"
  fi
  mkdir -p "$DEST_DIR"
  DEST_DIR="$(readlink -f "$DEST_DIR")"

  # Khôi phục đúng kiểu đầu vào
  if [[ "$ORIGIN_TYPE" == "dir" ]]; then
    # phải là tar -> giải nén ra thư mục tên gốc
    if detect_is_tar "$PAYLOAD_FILE"; then
      echo "→ Giải nén TAR vào: $DEST_DIR"
      tar -xf "$PAYLOAD_FILE" -C "$DEST_DIR"
      rm -f -- "$PAYLOAD_FILE"
      echo "✅ RESTORE hoàn tất (thư mục) → $DEST_DIR"
    else
      err "Kỳ vọng TAR cho ORIGIN_TYPE=dir nhưng không phải TAR: $PAYLOAD_FILE"
      exit 1
    fi
  else
    # file đơn -> ghi đúng tên gốc
    local OUT_FILE="$DEST_DIR/$ORIGIN_NAME"
    mv -f -- "$PAYLOAD_FILE" "$OUT_FILE"
    echo "✅ RESTORE hoàn tất (file) → $OUT_FILE"
  fi
}

# ---------- Main ----------
[[ $# -ge 1 ]] || { usage; exit 1; }
SUB="$1"; shift
case "$SUB" in
  pack)    cmd_pack "$@" ;;
  restore) cmd_restore "$@" ;;
  -h|--help) usage ;;
  *) err "Subcommand không hợp lệ: $SUB"; usage; exit 1 ;;
esac
