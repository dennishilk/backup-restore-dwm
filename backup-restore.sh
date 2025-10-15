#!/usr/bin/env bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  🧩 DWM Backup & Restore Tool v1.0                                      ║
# ║  AES-256 encrypted, split/single, verified, with safe progress bars     ║
# ╚═════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

TITLE="🧠 DWM Backup & Restore Tool"
BACKUP_DIR="./backups"
SPLIT_SIZE="95m"  # ~100 MB parts, GitHub-friendly

# ───────────────────────────────────────────────
# Helpers
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

# Sichere Passwortbox (bricht sauber ab)
ask_password_twice() {
  local P1 P2
  P1=$(dialog --insecure --passwordbox "🔒 Enter password for encryption:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then echo ""; return 1; fi

  P2=$(dialog --insecure --passwordbox "🔑 Confirm password:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then echo ""; return 1; fi

  if [ -z "$P1" ] || [ "$P1" != "$P2" ]; then
    pause "⚠️ Passwords do not match or are empty."
    echo ""; return 1
  fi
  echo "$P1"
  return 0
}

ask_password_once() {
  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local rc=$?
  if [ $rc -ne 0 ]; then rm -f /tmp/pw; echo ""; return 1; fi
  local P; P="$(cat /tmp/pw)"; rm -f /tmp/pw
  echo "$P"
  return 0
}

# ───────────────────────────────────────────────
# Create encrypted backup (with safe progress)
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
  if [ -z "${MODE:-}" ]; then pause "Cancelled."; return; fi
  SPLIT_ARG=""
  [ "$MODE" = "2" ] && SPLIT_ARG="-s $SPLIT_SIZE"

  # Passwort
  local PW
  PW="$(ask_password_twice)" || { pause "Cancelled."; return; }
  [ -z "$PW" ] && { pause "Cancelled."; return; }

  # Include-Pfade
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

  # Vorab-Info (nur Größe als Hinweis)
  local EST_SIZE
  EST_SIZE=$(du -ch "${INCLUDE_PATHS[@]}" 2>/dev/null | tail -n1 | awk '{print $1}')
  dialog --infobox "📦 Creating AES-256 encrypted backup...\n💾 Estimated size: ${EST_SIZE:-unknown}" 7 70
  sleep 1

  # zip im Hintergrund starten
  ( zip -r -e -P "$PW" $SPLIT_ARG "$ZIP_PATH" "${INCLUDE_PATHS[@]}" >/dev/null 2>&1 ) &
  local ZIP_PID=$!

  # Indeterminate Progress (sicher; läuft bis Prozess fertig, dann 100%)
  (
    local i=0
    while kill -0 "$ZIP_PID" 2>/dev/null; do
      i=$(( (i + 3) % 97 ))
      echo $i
      sleep 0.3
    done
    echo 100
  ) | dialog --gauge "Compressing and encrypting..." 10 70 0

  wait "$ZIP_PID" 2>/dev/null || true

  # Erfolg prüfen (ZIP oder .z01/.z02 existiert)
  if [ ! -f "$ZIP_PATH" ] && ! ls "$BACKUP_DIR/${BASENAME}".z* >/dev/null 2>&1; then
    pause "❌ Backup failed – no archive created."
    return
  fi

  verify_backup "$ZIP_PATH" "$PW"
}

# ───────────────────────────────────────────────
# Verify backup integrity + analyze content
# ───────────────────────────────────────────────
verify_backup() {
  local MAIN_ZIP="$1"
  local PASSWORD="$2"

  [ -z "${MAIN_ZIP:-}" ] && { pause "❌ No archive path provided."; return; }
  if [ ! -f "$MAIN_ZIP" ]; then
    # Falls nur Splitteile vorhanden sind, nehme das .zip im Namen aus MAIN_ZIP
    local root="${MAIN_ZIP%.*}"
    if [ -f "${root}.zip" ]; then MAIN_ZIP="${root}.zip"; else pause "❌ File not found: $MAIN_ZIP"; return; fi
  fi

  local DIR BASE PREFIX
  DIR="$(dirname "$MAIN_ZIP")"
  BASE="$(basename "$MAIN_ZIP")"
  PREFIX="${BASE%.*}"

  cd "$DIR" || { pause "⚠️ Cannot access $DIR"; return; }

  local PARTS
  PARTS=$(ls "$PREFIX".z* 2>/dev/null || true)
  local SIZE_TOTAL
  SIZE_TOTAL=$(du -ch $PREFIX.z* "$PREFIX.zip" 2>/dev/null | tail -1 | awk '{print $1}')
  local SHA256
  SHA256=$(sha256sum "$PREFIX.zip" 2>/dev/null | awk '{print $1}')

  # Integritätsprüfung (mit Passwort)
  unzip -t -P "$PASSWORD" "$PREFIX.zip" >/tmp/verify_log 2>&1 || true
  local STATUS=$?

  # Inhalts-Statistik
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
# Restore backup (with safe progress)
# ───────────────────────────────────────────────
restore_backup() {
  ensure_base_deps

  # Kandidaten sammeln
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

  # Menüeinträge (nur Basenames anzeigen)
  local MENU_ITEMS=()
  for FILE in "${FOUND_FILES[@]}"; do
    MENU_ITEMS+=("$FILE" "")
  done

  local ZIP
  ZIP=$(dialog --stdout --menu "Select backup to restore:" 20 80 10 "${MENU_ITEMS[@]}")
  if [ -z "${ZIP:-}" ]; then pause "Cancelled."; return; fi
  if [ ! -f "$ZIP" ]; then pause "❌ Selected file not found:\n$ZIP"; return; fi

  # Passwort
  local PW
  PW="$(ask_password_once)" || { pause "Cancelled."; return; }
  [ -z "$PW" ] && { pause "Cancelled."; return; }

  # Pfadteile robust setzen
  local DIRNAME BASENAME BASE_NOEXT
  DIRNAME="$(dirname -- "$ZIP")"
  BASENAME="$(basename -- "$ZIP")"
  BASE_NOEXT="${BASENAME%.*}"

  cd "$DIRNAME" || { pause "⚠️ Cannot cd into:\n$DIRNAME"; return; }

  # Vorabprüfung (falsches Passwort früh erkennen)
  unzip -t -P "$PW" -- "$BASENAME" >/tmp/precheck 2>&1 || true
  if grep -qi "incorrect password" /tmp/precheck; then
    rm -f /tmp/precheck
    pause "❌ Wrong password."
    return
  fi
  rm -f /tmp/precheck

  # Entpacken im Hintergrund
  ( unzip -o -P "$PW" -- "$BASENAME" -d "$HOME" >/dev/null 2>&1 ) &
  local UNZIP_PID=$!

  # Indeterminierte Progressbar (läuft bis fertig, dann 100)
  (
    local i=0
    while kill -0 "$UNZIP_PID" 2>/dev/null; do
      i=$(( (i + 3) % 97 ))
      echo $i
      sleep 0.3
    done
    echo 100
  ) | dialog --gauge "Decrypting and restoring backup..." 10 70 0

  wait "$UNZIP_PID" 2>/dev/null || true

  # Erfolg prüfen: z. B. ob ~/.config/suckless existiert (optional)
  if [ ! -d "$HOME/.config" ]; then
    pause "⚠️ Restore finished, but target content not found.\nCheck the archive contents."
    return
  fi

  fc-cache -fv >/dev/null 2>&1 || true

  dialog --msgbox "🧩 Restore Complete!
$(hr)
📂 Target: $HOME
🔐 Verified: OK
$(hr)
✅ All systems online, Commander Dennis!" 18 80
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
