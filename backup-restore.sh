#!/usr/bin/env bash
# ╔════════════════════════════════════════════╗
# ║  DWM Backup & Restore Tool (Minimal v2.0)  ║
# ║  Author: Dennis Hilk                       ║
# ║  Features: AES-256 Encrypted Backups       ║
# ╚════════════════════════════════════════════╝

set -euo pipefail

TITLE="🧩 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"

# ────────────────────────────────────────────────────────────────
# Helper functions
# ────────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || sudo apt install -y "$1"; }
pause() { dialog --msgbox "$1" 10 70; }

ensure_base_deps() {
  sudo apt update -y >/dev/null 2>&1
  for p in dialog zip unzip; do need "$p"; done
}

# ────────────────────────────────────────────────────────────────
# Create encrypted backup (AES-256 + split)
# ────────────────────────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  local TS=$(date +%Y-%m-%d_%H-%M)
  local BASENAME="dwm-backup_$TS"
  local TARGET_DIR="$BACKUP_DIR"

  dialog --insecure --passwordbox "Enter password for encryption:" 10 60 2> /tmp/pw
  local PW=$(cat /tmp/pw); rm /tmp/pw

  dialog --infobox "📦 Creating encrypted split archive..." 5 60
  zip -r -e -P "$PW" -s "$SPLIT_SIZE" \
      "$TARGET_DIR/$BASENAME.zip" \
      "$HOME/.config/suckless" "$HOME/.zshrc" "$HOME/.p10k.zsh" >/dev/null 2>&1

  local COUNT=$(ls "$TARGET_DIR"/"$BASENAME"*.z* 2>/dev/null | wc -l)
  pause "✅ Backup complete!\n\nSaved in:\n$TARGET_DIR\n($COUNT file parts total)"
}

# ────────────────────────────────────────────────────────────────
# Restore encrypted backup (detects in ./backups or tool folder)
# ────────────────────────────────────────────────────────────────
restore_backup() {
  ensure_base_deps

  local SEARCH_DIRS=(
    "$BACKUP_DIR"
    "$(dirname "$(realpath "$0")")"
  )

  local FOUND_FILES=()
  for DIR in "${SEARCH_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
      while IFS= read -r -d '' f; do
        FOUND_FILES+=("$f")
      done < <(find "$DIR" -maxdepth 1 -type f -name "*.zip" -print0 2>/dev/null)
    fi
  done

  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    pause "⚠️ No backup ZIPs found in:\n${SEARCH_DIRS[*]}"
    return
  fi

  local MENU_ITEMS=()
  for FILE in "${FOUND_FILES[@]}"; do
    MENU_ITEMS+=("$FILE" "")
  done

  local ZIP
  ZIP=$(dialog --stdout --menu "Select backup to restore:" 20 80 10 "${MENU_ITEMS[@]}")
  [ -z "$ZIP" ] && pause "Cancelled." && return

  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local PW=$(cat /tmp/pw); rm /tmp/pw

  local DIRNAME=$(dirname "$ZIP")
  local BASENAME=$(basename "$ZIP")
  local BASE_NOEXT="${BASENAME%.*}"

  cd "$DIRNAME"

  echo "🔎 Checking for split parts..."
  ls "$BASE_NOEXT".z* 2>/dev/null || echo "(no split parts found)"

  unzip -P "$PW" "$ZIP" -d "$HOME" >/dev/null 2>&1 \
    || { pause "❌ Wrong password or corrupted archive."; return; }

  fc-cache -fv >/dev/null 2>&1 || true
  pause "✅ Backup restored successfully to $HOME"
}

# ────────────────────────────────────────────────────────────────
# Main Menu
# ────────────────────────────────────────────────────────────────
main_menu() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"

  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" \
      --menu "Choose an action:" 15 70 5 \
      1 "🔒 Create encrypted backup (AES-256)" \
      2 "🔐 Restore encrypted backup" \
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
