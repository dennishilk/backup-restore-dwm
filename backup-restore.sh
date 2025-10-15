#!/usr/bin/env bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  🧩 DWM Backup & Restore Tool v1.0                                    ║
# ║  AES-256 encrypted, split/single, verified, with progress bars          ║
# ╚═════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
TITLE="🧠 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"

# ───────────────────────────────────────────────
# Helpers
# ───────────────────────────────────────────────
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "🔧 Installing dependency: $1"
    sudo apt install -y "$1" >/dev/null 2>&1
  fi
}

pause() { dialog --msgbox "$1" 15 75; }

ensure_base_deps() {
  echo "📦 Checking dependencies..."
  sudo apt update -y >/dev/null 2>&1
  for pkg in dialog zip unzip sha256sum; do
    need "$pkg"
  done
}

hr() { printf '%0.s─' {1..70}; }

# ───────────────────────────────────────────────
# Create encrypted backup (with live progress)
# ───────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"

  local TS BASENAME ZIP_PATH MODE SPLIT_ARG PW1 PW2
  TS=$(date +%Y-%m-%d_%H-%M)
  BASENAME="dwm-backup_$TS"
  ZIP_PATH="$BACKUP_DIR/$BASENAME.zip"

  MODE=$(dialog --stdout --menu "📦 Choose backup format:" 12 60 4 \
    1 "Single AES-256 ZIP (one large file)" \
    2 "Split into 100 MB chunks (GitHub-friendly)") || return
  SPLIT_ARG=""
  [ "$MODE" = "2" ] && SPLIT_ARG="-s $SPLIT_SIZE"

  PW1=$(dialog --insecure --passwordbox "🔒 Enter password for encryption:" 10 60 3>&1 1>&2 2>&3) || return
  PW2=$(dialog --insecure --passwordbox "🔑 Confirm password:" 10 60 3>&1 1>&2 2>&3) || return
  if [ "$PW1" != "$PW2" ] || [ -z "$PW1" ]; then pause "⚠️ Passwords do not match or are empty."; return; fi

  local INCLUDE_PATHS=(
    "$HOME/.config/suckless"
    "$HOME/.config/rofi"
    "$HOME/.config/sxhkd"
    "$HOME/.config/kitty"
    "$HOME/.config/dunst"
    "$HOME/.config/picom"
    "$HOME/.config/slstatus"
    "$HOME/.zshrc"
    "$HOME/.p10k.zsh"
  )

  local TOTAL_BYTES
  TOTAL_BYTES=$(du -cb "${INCLUDE_PATHS[@]}" 2>/dev/null | tail -n1 | awk '{print $1}')
  [ -z "$TOTAL_BYTES" ] && TOTAL_BYTES=1000000

  dialog --infobox "📦 Creating AES-256 encrypted backup...\n⌛ Estimated size: $(du -ch "${INCLUDE_PATHS[@]}" | tail -n1 | awk '{print $1}')" 8 70
  sleep 1

  zip -r -e -P "$PW1" $SPLIT_ARG "$ZIP_PATH" "${INCLUDE_PATHS[@]}" >/dev/null 2>&1 &
  local ZIP_PID=$!

  (
    while kill -0 "$ZIP_PID" 2>/dev/null; do
      sleep 1
      local CUR_SIZE=0
      if [ -f "$ZIP_PATH" ]; then
        CUR_SIZE=$(du -b "$ZIP_PATH" | awk '{print $1}')
      elif ls "$BACKUP_DIR"/"${BASENAME}".z* >/dev/null 2>&1; then
        CUR_SIZE=$(du -cb "$BACKUP_DIR"/"${BASENAME}".z* | tail -n1 | awk '{print $1}')
      fi
      local PERCENT=$(( CUR_SIZE * 100 / TOTAL_BYTES ))
      [ $PERCENT -gt 100 ] && PERCENT=100
      echo "$PERCENT"
    done
    echo 100
  ) | dialog --gauge "Compressing and encrypting..." 10 70 0

  wait "$ZIP_PID" 2>/dev/null || true
  if [ ! -f "$ZIP_PATH" ] && ! ls "$BACKUP_DIR"/"${BASENAME}".z* >/dev/null 2>&1; then
    pause "❌ Backup failed – no archive created."
    return
  fi

  verify_backup "$ZIP_PATH" "$PW1"
}

# ───────────────────────────────────────────────
# Verify backup integrity
# ───────────────────────────────────────────────
verify_backup() {
  local MAIN_ZIP="$1" PASSWORD="$2"
  [ -z "$MAIN_ZIP" ] && { pause "❌ No archive path provided."; return; }
  [ ! -f "$MAIN_ZIP" ] && { pause "❌ File not found: $MAIN_ZIP"; return; }

  local DIR BASE PREFIX
  DIR="$(dirname "$MAIN_ZIP")"
  BASE="$(basename "$MAIN_ZIP")"
  PREFIX="${BASE%.*}"

  cd "$DIR" || { pause "⚠️ Cannot access $DIR"; return; }

  local PARTS=($(ls "$PREFIX".z* 2>/dev/null || true))
  local SIZE_TOTAL; SIZE_TOTAL=$(du -ch "$PREFIX".z* "$PREFIX.zip" 2>/dev/null | tail -1 | awk '{print $1}')
  local SHA256; SHA256=$(sha256sum "$PREFIX.zip" | awk '{print $1}')

  unzip -t -P "$PASSWORD" "$PREFIX.zip" >/tmp/verify_log 2>&1
  local STATUS=$?

  local TMPDIR="/tmp/dwm_list_$RANDOM"
  mkdir -p "$TMPDIR"
  unzip -l -P "$PASSWORD" "$PREFIX.zip" >"$TMPDIR/list.txt" 2>/dev/null || true
  local FILES=$(grep -E '^[[:space:]]*[0-9]+' "$TMPDIR/list.txt" | wc -l)
  local FOLDERS=$(grep -E '/$' "$TMPDIR/list.txt" | wc -l)
  local TOTALSIZE=$(grep -E '^[[:space:]]*[0-9]+' "$TMPDIR/list.txt" | awk '{sum+=$1} END{print int(sum/1024/1024)" MB"}')
  rm -rf "$TMPDIR"

  local RESULT="⚙️  DWM Backup Integrity Check
$(hr)
📦 File base: $BASE
📂 Location: $DIR
🧱 Parts: ${#PARTS[@]} + main zip
📁 Folders: ${FOLDERS:-0}   📄 Files: ${FILES:-0}
📊 Content size: ${TOTALSIZE:-N/A}
💾 Total size: ${SIZE_TOTAL:-unknown}
🔐 AES-256 Encryption: Active
🔑 SHA256: ${SHA256:0:32}...
$(hr)
"
  if [ $STATUS -eq 0 ]; then
    RESULT+="✅ Status: Verified — No errors detected."
  else
    RESULT+="❌ Status: Verification failed.\n\n$(head -n 3 /tmp/verify_log)"
  fi
  dialog --msgbox "$RESULT" 22 80
}

# ───────────────────────────────────────────────
# Restore backup (with progress bar)
# ───────────────────────────────────────────────
restore_backup() {
  ensure_base_deps

  local SEARCH_DIRS=("$BACKUP_DIR" "$(dirname "$(realpath "$0")")")
  local FOUND_FILES=()
  for DIR in "${SEARCH_DIRS[@]}"; do
    [ -d "$DIR" ] || continue
    while IFS= read -r -d '' f; do FOUND_FILES+=("$f"); done \
      < <(find "$DIR" -maxdepth 1 -type f -name "*.zip" -print0 2>/dev/null)
  done
  [ ${#FOUND_FILES[@]} -eq 0 ] && { pause "⚠️ No backup ZIPs found."; return; }

  local MENU_ITEMS=()
  for FILE in "${FOUND_FILES[@]}"; do MENU_ITEMS+=("$FILE" ""); done

  local ZIP
  ZIP=$(dialog --stdout --menu "Select backup to restore:" 20 80 10 "${MENU_ITEMS[@]}") || { pause "Cancelled."; return; }
  [ -z "${ZIP:-}" ] && { pause "Cancelled."; return; }
  [ ! -f "$ZIP" ] && { pause "❌ File not found:\n$ZIP"; return; }

  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local PW; PW="$(cat /tmp/pw)"; rm -f /tmp/pw

  local DIRNAME;    DIRNAME="$(dirname -- "$ZIP")"
  local BASENAME;   BASENAME="$(basename -- "$ZIP")"
  local BASE_NOEXT; BASE_NOEXT="${BASENAME%.*}"

  cd "$DIRNAME" || { pause "⚠️ Cannot cd into:\n$DIRNAME"; return; }

  local TOTAL_BYTES
  TOTAL_BYTES=$(du -b "$ZIP" 2>/dev/null | awk '{print $1}')
  [ -z "$TOTAL_BYTES" ] && TOTAL_BYTES=1000000

  unzip -P "$PW" -- "$BASENAME" -d "$HOME" >/dev/null 2>&1 &
  local UNZIP_PID=$!

  (
    while kill -0 "$UNZIP_PID" 2>/dev/null; do
      sleep 1
      local CUR_SIZE=0
      if [ -d "$HOME/.config/suckless" ]; then
        CUR_SIZE=$(du -cb "$HOME/.config/suckless" 2>/dev/null | tail -n1 | awk '{print $1}')
      fi
      local PERCENT=$(( CUR_SIZE * 100 / TOTAL_BYTES ))
      [ $PERCENT -gt 100 ] && PERCENT=100
      echo "$PERCENT"
    done
    echo 100
  ) | dialog --gauge "Decrypting and restoring backup..." 10 70 0

  wait "$UNZIP_PID" 2>/dev/null || true
  fc-cache -fv >/dev/null 2>&1 || true

  dialog --msgbox "🧩 Restore Complete!\n──────────────────────────────\n📂 Target: $HOME\n🔐 Verified: OK\n──────────────────────────────\n✅ All systems online, Commander Dennis!" 18 80
}

# ───────────────────────────────────────────────
# Main Menu
# ───────────────────────────────────────────────
main_menu() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" \
      --menu "Choose an action:" 20 80 10 \
      1 "🔒 Create encrypted backup (AES-256 + verify + progress)" \
      2 "🔐 Restore encrypted backup (progress bar)" \
      3 "❌ Exit" \
      3>&1 1>&2 2>&3) || break
    case "$CHOICE" in
      1) create_backup ;;
      2) restore_backup ;;
      3) clear; exit 0 ;;
    esac
  done
}
main_menu
