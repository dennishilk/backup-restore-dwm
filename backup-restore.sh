#!/usr/bin/env bash
# ╔════════════════════════════════════════════╗
# ║  DWM Backup & Restore Tool (Minimal v1.0)  ║
# ║  Author: Dennis Hilk                       ║
# ║  Features: AES-256 Encrypted Backups       ║
# ╚════════════════════════════════════════════╝

set -euo pipefail

TITLE="🧩 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || sudo apt install -y "$1"; }
pause() { dialog --msgbox "$1" 10 70; }

ensure_base_deps() {
  sudo apt update -y >/dev/null 2>&1
  for p in dialog zip unzip; do need "$p"; done
}

# ─────────────────────────────────────────────
# Create encrypted backup (AES-256 + split)
# ─────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"

  local TS=$(date +%Y-%m-%d_%H-%M)
  local BASENAME="dwm-backup_$TS"
  local TARGET_DIR="$BACKUP_DIR"
  local ZIP_PATH="$TARGET_DIR/$BASENAME.zip"

  # Password confirmation
  local PW1 PW2
  PW1=$(dialog --insecure --passwordbox "Enter password for encryption:" 10 60 3>&1 1>&2 2>&3) || return
  PW2=$(dialog --insecure --passwordbox "Confirm password:" 10 60 3>&1 1>&2 2>&3) || return
  if [ "$PW1" != "$PW2" ] || [ -z "$PW1" ]; then
    pause "⚠️ Passwords do not match or are empty."
    return
  fi

  dialog --infobox "📦 Creating AES-256 encrypted split archive..." 5 60
  sleep 0.5

  # Include folders and files for full DWM environment
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

  zip -r -e -P "$PW1" -s "$SPLIT_SIZE" "$ZIP_PATH" "${INCLUDE_PATHS[@]}" >/dev/null 2>&1

  if [ ! -f "$ZIP_PATH" ]; then
    pause "❌ Backup failed – no archive created."
    return
  fi

  local PARTS
  PARTS=$(ls "$TARGET_DIR/$BASENAME".z* 2>/dev/null || true)
  pause "✅ Backup created successfully!\n\nSaved as:\n$ZIP_PATH\n\nSplit parts:\n${PARTS:-none}"
}

# ─────────────────────────────────────────────
# Restore encrypted backup (split-aware + checks)
# ─────────────────────────────────────────────
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
  local PARTS_FOUND=()
  for f in "$BASE_NOEXT".z*; do
    [ -f "$f" ] && PARTS_FOUND+=("$f")
  done

  if [ ${#PARTS_FOUND[@]} -gt 0 ]; then
    echo "✅ Found split parts:"
    printf '%s\n' "${PARTS_FOUND[@]}"
  else
    echo "ℹ️ No split parts found (single ZIP)."
  fi

  echo
  echo "🔓 Decrypting and extracting..."
  unzip -P "$PW" "$BASENAME" -d "$HOME" >/tmp/unzip_log 2>&1
  local STATUS=$?

  if [ $STATUS -ne 0 ]; then
    if grep -qi "incorrect password" /tmp/unzip_log; then
      pause "❌ Wrong password. Please try again."
    elif grep -qi "End-of-central-directory signature not found" /tmp/unzip_log; then
      pause "⚠️ Archive appears incomplete or split parts are missing."
    else
      pause "⚠️ Extraction failed.\n\nError log:\n$(head -n 5 /tmp/unzip_log)"
    fi
    rm /tmp/unzip_log
    return
  fi

  rm /tmp/unzip_log
  fc-cache -fv >/dev/null 2>&1 || true
  pause "✅ Backup restored successfully to $HOME"
}

# ─────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────
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
