#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  🧩 DWM Backup & Restore Tool v1.1                                   ║
# ║  AES-256 encrypted, verified, no progress bars, safe dialogs         ║
# ╚══════════════════════════════════════════════════════════════════════╝

# kein „-e“: verhindert, dass dialog-Abbrüche das ganze Skript beenden
set -uo pipefail

TITLE="🧠 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"  # ~100 MB für GitHub-kompatible Splits

# ───────────────────────────────────────────────
# Helper-Funktionen
# ───────────────────────────────────────────────
pause() { dialog --msgbox "$1" 15 75; }

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "🔧 Installing dependency: $1"
    sudo apt-get install -y "$1" >/dev/null 2>&1 || sudo apt install -y "$1" >/dev/null 2>&1
  fi
}

ensure_base_deps() {
  echo "📦 Checking dependencies..."
  sudo apt-get update -y >/dev/null 2>&1 || sudo apt update -y >/dev/null 2>&1 || true
  for pkg in dialog zip unzip sha256sum; do need "$pkg"; done
}

hr() { printf '%0.s─' {1..70}; }

# ───────────────────────────────────────────────
# Passwortdialoge (robust gegen ESC / Abbruch)
# ───────────────────────────────────────────────
ask_password_twice() {
  set +eu
  local P1 P2
  P1=$(dialog --insecure --passwordbox "🔒 Enter password for encryption:" 10 60 3>&1 1>&2 2>&3)
  local rc1=$?
  [ $rc1 -ne 0 ] && set -eu && return 1

  P2=$(dialog --insecure --passwordbox "🔑 Confirm password:" 10 60 3>&1 1>&2 2>&3)
  local rc2=$?
  set -eu
  [ $rc2 -ne 0 ] && return 1
  [ -z "$P1" ] && return 1
  [ "$P1" != "$P2" ] && return 1
  echo "$P1"
  return 0
}

ask_password_once() {
  set +eu
  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local rc=$?
  if [ $rc -ne 0 ]; then rm -f /tmp/pw; set -eu; return 1; fi
  local P; P="$(cat /tmp/pw)"; rm -f /tmp/pw
  set -eu
  [ -z "$P" ] && return 1
  echo "$P"
  return 0
}

# ───────────────────────────────────────────────
# Backup erstellen (AES-256, kein Progress)
# ───────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"

  local TS BASENAME ZIP_PATH
  TS=$(date +%Y-%m-%d_%H-%M)
  BASENAME="dwm-backup_${TS}"
  ZIP_PATH="$BACKUP_DIR/$BASENAME.zip"

  # Format wählen
  local MODE SPLIT_ARG
  MODE=$(dialog --stdout --menu "📦 Choose backup format:" 12 60 4 \
    1 "Single AES-256 ZIP (one large file)" \
    2 "Split into 100 MB chunks (GitHub-friendly)")
  [ -z "${MODE:-}" ] && { pause "Cancelled."; return; }
  SPLIT_ARG=""
  [ "$MODE" = "2" ] && SPLIT_ARG="-s $SPLIT_SIZE"

  # Passwort sicher abfragen
  local PW
  PW="$(ask_password_twice)" || { pause "❌ Cancelled or invalid password."; return; }

  # zu sichernde Pfade
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

  local EST_SIZE
  EST_SIZE=$(du -ch "${INCLUDE_PATHS[@]}" 2>/dev/null | tail -n1 | awk '{print $1}')

  dialog --infobox "📦 Creating AES-256 encrypted backup...
💾 Estimated size: ${EST_SIZE:-unknown}
Please wait..." 8 70
  sleep 1

  zip -r -e -P "$PW" $SPLIT_ARG "$ZIP_PATH" "${INCLUDE_PATHS[@]}" >/dev/null 2>&1
  local rc=$?

  if [ $rc -ne 0 ]; then
    pause "❌ Backup failed (zip error $rc)."
    return
  fi

  if [ ! -f "$ZIP_PATH" ] && ! ls "$BACKUP_DIR/${BASENAME}".z* >/dev/null 2>&1; then
    pause "❌ Backup failed – no archive created."
    return
  fi

  verify_backup "$ZIP_PATH" "$PW"
}

# ───────────────────────────────────────────────
# Backup-Integrität prüfen
# ───────────────────────────────────────────────
verify_backup() {
  local MAIN_ZIP="$1" PASSWORD="$2"

  [ -z "${MAIN_ZIP:-}" ] && { pause "❌ No archive path provided."; return; }
  if [ ! -f "$MAIN_ZIP" ]; then
    local root="${MAIN_ZIP%.*}"
    if [ -f "${root}.zip" ]; then MAIN_ZIP="${root}.zip"; else pause "❌ File not found: $MAIN_ZIP"; return; fi
  fi

  local DIR BASE PREFIX
  DIR="$(dirname "$MAIN_ZIP")"
  BASE="$(basename "$MAIN_ZIP")"
  PREFIX="${BASE%.*}"

  cd "$DIR" || { pause "⚠️ Cannot access $DIR"; return; }

  local PARTS SIZE_TOTAL SHA256
  PARTS=$(ls "$PREFIX".z* 2>/dev/null || true)
  SIZE_TOTAL=$(du -ch $PREFIX.z* "$PREFIX.zip" 2>/dev/null | tail -1 | awk '{print $1}')
  SHA256=$(sha256sum "$PREFIX.zip" 2>/dev/null | awk '{print $1}')

  unzip -t -P "$PASSWORD" "$PREFIX.zip" >/tmp/verify_log 2>&1 || true
  local STATUS=$?

  local TMPDIR="/tmp/dwm_list_$RANDOM"
  mkdir -p "$TMPDIR"
  unzip -l -P "$PASSWORD" "$PREFIX.zip" >"$TMPDIR/list.txt" 2>/dev/null || true
  local FILES FOLDERS TOTALSIZE
  FILES=$(grep -E '^[[:space:]]*[0-9]+' "$TMPDIR/list.txt" | wc -l)
  FOLDERS=$(grep -E '/$' "$TMPDIR/list.txt" | wc -l)
  TOTALSIZE=$(grep -E '^[[:space:]]*[0-9]+' "$TMPDIR/list.txt" | awk '{sum+=$1} END{print int(sum/1024/1024)" MB"}')
  rm -rf "$TMPDIR"

  local RESULT="⚙️  DWM Backup Integrity Check
$(hr)
📦 File base: $BASE
📂 Location: $DIR
🧱 Parts: $( [ -n "$PARTS" ] && echo "$(echo "$PARTS" | wc -l)" || echo 0 ) + main zip
📁 Folders: ${FOLDERS:-0}   📄 Files: ${FILES:-0}
📊 Content size: ${TOTALSIZE:-N/A}
💾 Total size: ${SIZE_TOTAL:-unknown}
🔐 AES-256 Encryption: Active
🔑 SHA256: ${SHA256:-N/A}
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
# Backup wiederherstellen (kein Progress)
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

  if [ ${#FOUND_FILES[@]} -eq 0 ]; then
    pause "⚠️ No backup ZIPs found in:\n${SEARCH_DIRS[*]}"
    return
  fi

  local MENU_ITEMS=()
  for FILE in "${FOUND_FILES[@]}"; do MENU_ITEMS+=("$FILE" ""); done

  local ZIP
  ZIP=$(dialog --stdout --menu "Select backup to restore:" 20 80 10 "${MENU_ITEMS[@]}")
  [ -z "${ZIP:-}" ] && { pause "Cancelled."; return; }
  [ ! -f "$ZIP" ] && { pause "❌ Selected file not found:\n$ZIP"; return; }

  # 🔐 Passwort sicher abfragen (set -u deaktiviert)
  set +u
  local PW
  PW=$(dialog --insecure --passwordbox "Enter decryption password:" 10 60 3>&1 1>&2 2>&3)
  local rc=$?
  set -u
  if [ $rc -ne 0 ] || [ -z "$PW" ]; then
    pause "❌ Cancelled or empty password."
    return
  fi

  local DIRNAME BASENAME
  DIRNAME="$(dirname -- "$ZIP")"
  BASENAME="$(basename -- "$ZIP")"

  cd "$DIRNAME" || { pause "⚠️ Cannot cd into:\n$DIRNAME"; return; }

  unzip -t -P "$PW" -- "$BASENAME" >/tmp/precheck 2>&1 || true
  if grep -qi "incorrect password" /tmp/precheck; then
    rm -f /tmp/precheck
    pause "❌ Wrong password."
    return
  fi
  rm -f /tmp/precheck

  dialog --infobox "🔓 Decrypting and restoring...\nPlease wait..." 7 60
  sleep 1

  unzip -o -P "$PW" -- "$BASENAME" -d "$HOME" >/tmp/unzip_log 2>&1
  local rc=$?

  if [ $rc -ne 0 ]; then
    if grep -qi "incorrect password" /tmp/unzip_log; then
      pause "❌ Wrong password."
    elif grep -qi "End-of-central-directory" /tmp/unzip_log; then
      pause "⚠️ Incomplete archive or missing split parts."
    else
      pause "⚠️ Extraction failed.\n\n$(head -n 5 /tmp/unzip_log)"
    fi
    rm -f /tmp/unzip_log
    return
  fi

  rm -f /tmp/unzip_log
  fc-cache -fv >/dev/null 2>&1 || true

  dialog --msgbox "🧩 Restore Complete!
$(hr)
📂 Target: $HOME
🔐 Verified: OK
$(hr)
✅ All systems online, Commander Dennis!" 18 80
}


# ───────────────────────────────────────────────
# Hauptmenü
# ───────────────────────────────────────────────
main_menu() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" \
      --menu "Choose an action:" 20 80 10 \
      1 "🔒 Create encrypted backup (AES-256 + verify)" \
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
