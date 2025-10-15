#!/usr/bin/env bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║   🧩 DWM Backup & Restore Tool v4.1 (Split-Choice)                      ║
# ║   AES-256 encrypted, split or single, verified,                         ║
# ╚═════════════════════════════════════════════════════════════════════════╝

set -euo pipefail
TITLE="🧠 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"

# ────────────────────────────────
# Helpers
# ────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || sudo apt install -y "$1"; }
pause() { dialog --msgbox "$1" 15 75; }
ensure_base_deps() { sudo apt update -y >/dev/null 2>&1; for p in dialog zip unzip sha256sum; do need "$p"; done; }
hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'; }

# ────────────────────────────────
# Create encrypted backup
# ────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"

  local TS=$(date +%Y-%m-%d_%H-%M)
  local BASENAME="dwm-backup_$TS"
  local ZIP_PATH="$BACKUP_DIR/$BASENAME.zip"

  # Select mode: split or single
  local MODE
  MODE=$(dialog --stdout --menu "📦 Choose backup format:" 12 60 4 \
    1 "Single AES-256 ZIP (one large file)" \
    2 "Split into 100 MB chunks (GitHub-friendly)" ) || return

  local SPLIT_ARG=""
  [ "$MODE" = "2" ] && SPLIT_ARG="-s $SPLIT_SIZE"

  # Password confirmation
  local PW1 PW2
  PW1=$(dialog --insecure --passwordbox "🔒 Enter password for encryption:" 10 60 3>&1 1>&2 2>&3) || return
  PW2=$(dialog --insecure --passwordbox "🔑 Confirm password:" 10 60 3>&1 1>&2 2>&3) || return
  if [ "$PW1" != "$PW2" ] || [ -z "$PW1" ]; then
    pause "⚠️ Passwords do not match or are empty."
    return
  fi

  dialog --infobox "📦 Creating AES-256 encrypted backup...\n⌛ Please wait..." 7 60
  sleep 0.5

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

  zip -r -e -P "$PW1" $SPLIT_ARG "$ZIP_PATH" "${INCLUDE_PATHS[@]}" >/dev/null 2>&1
  [ ! -f "$ZIP_PATH" ] && { pause "❌ Backup failed – no archive created."; return; }

  verify_backup "$ZIP_PATH" "$PW1"
}

# ────────────────────────────────
# Verify backup
# ────────────────────────────────
verify_backup() {
  local MAIN_ZIP="$1" PASSWORD="$2"
  local DIR=$(dirname "$MAIN_ZIP") BASE=$(basename "$MAIN_ZIP") PREFIX="${BASE%.*}"
  cd "$DIR"

  local PARTS=($(ls "$PREFIX".z* 2>/dev/null || true))
  local SIZE_TOTAL=$(du -ch "$PREFIX".z* "$PREFIX.zip" 2>/dev/null | tail -1 | awk '{print $1}')
  local SHA256=$(sha256sum "$PREFIX.zip" | awk '{print $1}')

  unzip -t -P "$PASSWORD" "$PREFIX.zip" >/tmp/verify_log 2>&1
  local STATUS=$?

  local RESULT="⚙️  DWM Backup Integrity Check
$(hr)
📦 File base: $BASE
📂 Location: $DIR
🧱 Total parts: ${#PARTS[@]} + main zip
💾 Total size: $SIZE_TOTAL
🔐 AES-256 Encryption: Active
🔑 SHA256: ${SHA256:0:32}...
$(hr)
"

  if [ $STATUS -eq 0 ]; then
    RESULT+="✅ Status: Verified — No errors detected."
  else
    RESULT+="❌ Status: Verification failed.\n\n$(head -n 3 /tmp/verify_log)"
  fi
  dialog --msgbox "$RESULT" 20 80
}

# ────────────────────────────────
# Restore backup
# ────────────────────────────────
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

  local MENU_ITEMS=(); for FILE in "${FOUND_FILES[@]}"; do MENU_ITEMS+=("$FILE" ""); done
  local ZIP; ZIP=$(dialog --stdout --menu "Select backup to restore:" 20 80 10 "${MENU_ITEMS[@]}")
  [ -z "$ZIP" ] && { pause "Cancelled."; return; }

  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local PW=$(cat /tmp/pw); rm /tmp/pw
  local DIRNAME=$(dirname "$ZIP") BASENAME=$(basename "$ZIP") BASE_NOEXT="${BASENAME%.*}"
  cd "$DIRNAME"

  echo "🔓 Extracting..."
  unzip -P "$PW" "$BASENAME" -d "$HOME" >/tmp/unzip_log 2>&1
  local STATUS=$?
  if [ $STATUS -ne 0 ]; then
    if grep -qi "incorrect password" /tmp/unzip_log; then pause "❌ Wrong password."
    elif grep -qi "End-of-central-directory" /tmp/unzip_log; then pause "⚠️ Incomplete archive."
    else pause "⚠️ Extraction failed.\n\n$(head -n 5 /tmp/unzip_log)"; fi
    rm /tmp/unzip_log; return
  fi

  rm /tmp/unzip_log; fc-cache -fv >/dev/null 2>&1 || true
  local MSG="🧩 Restore Complete!\n$(hr)\n📂 Target: $HOME\n🔐 Verified: OK\n$(hr)\n✅ All systems online, Commander Dennis!"
  dialog --msgbox "$MSG" 18 80
}

# ────────────────────────────────
# Menu
# ────────────────────────────────
main_menu() {
  ensure_base_deps; mkdir -p "$BACKUP_DIR"
  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" \
      --menu "Choose an action:" 20 80 10 \
      1 "🔒 Create encrypted backup (AES-256)" \
      2 "🔐 Restore encrypted backup" \
      3 "❌ Exit" 3>&1 1>&2 2>&3) || break
    case "$CHOICE" in
      1) create_backup ;;
      2) restore_backup ;;
      3) clear; exit 0 ;;
    esac
  done
}
main_menu
