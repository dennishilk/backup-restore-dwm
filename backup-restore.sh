#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  Desktop Backup Tool (DWM & dotfiles) – Encrypted + Split
#  Author: Dennis Hilk (for dennishilk)
#  Features: dialog UI, AES-256 encryption, split archives (<100MB)
#  Works on Debian 13 Minimal (auto-installs zip/unzip/dialog)
# ──────────────────────────────────────────────────────────────

set -o pipefail

# ── CONFIG ────────────────────────────────────────────────────
BACKUP_DIR="$(pwd)/backups"     # Zielordner für Backups (relativ zum Start-Ordner)
SPLIT_SIZE="95m"                # Chunk-Größe für gesplittete ZIPs (GitHub <100MB)
TMP_DIR="$BACKUP_DIR/.tmp"      # temporäres Arbeitsverzeichnis

# Standard-Auswahl (Checkliste) – passe nach Bedarf an
INCLUDE_PATHS=(
  "$HOME/.config/suckless"
  "$HOME/.config/kitty"
  "$HOME/.config/rofi"
  "$HOME/.config/dunst"
  "$HOME/.config/picom"
  "$HOME/.config/sxhkd"
  "$HOME/.zshrc"
  "$HOME/.p10k.zsh"
  "$HOME/.oh-my-zsh"
  "$HOME/.local/share/fonts"
  "$HOME/bin"
  "$HOME/.local/bin"
)

# ── HELPER ────────────────────────────────────────────────────
need_pkg() {
  local pkg="$1"
  if ! command -v "$pkg" &>/dev/null; then
    sudo apt update -y >/dev/null 2>&1
    sudo apt install -y "$pkg" >/dev/null 2>&1
  fi
}

ensure_deps() {
  for p in dialog zip unzip; do
    need_pkg "$p"
  done
  mkdir -p "$BACKUP_DIR" "$TMP_DIR"
}

pause_msg() {
  dialog --msgbox "$1" 10 70
}

# Prüft, ob ein Pfad existiert, dann kopieren
copy_safe() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    cp -a "$src" "$dst" 2>/dev/null
  fi
}

# Listet erzeugte Teile hübsch auf
list_parts() {
  local base="$1"
  ls -1 "${base}".z?? 2>/dev/null
  ls -1 "${base}.zip" 2>/dev/null
}

# ── BACKUP ────────────────────────────────────────────────────
create_backup() {
  ensure_deps
  local DATE BASENAME WORK
  DATE=$(date +%Y-%m-%d_%H-%M)
  BASENAME="desktop-backup_${DATE}"
  WORK="$TMP_DIR/$BASENAME"
  rm -rf "$WORK"
  mkdir -p "$WORK/config" "$WORK/home" "$WORK/fonts"

  # Checkliste anzeigen
  local items=()
  local idx=1
  for path in "${INCLUDE_PATHS[@]}"; do
    items+=("$idx" "$path" "on")
    ((idx++))
  done

  local pick
  pick=$(dialog --stdout --separate-output --checklist "Select items to include in the backup:" 20 80 12 "${items[@]}")
  [ -z "$pick" ] && pause_msg "Backup canceled." && return

  dialog --infobox "📦 Collecting files..." 5 50
  sleep 0.3

  # Auswahl kopieren
  idx=1
  while read -r sel; do
    for p in "${INCLUDE_PATHS[@]}"; do
      if [ "$sel" -eq "$idx" ]; then
        case "$p" in
          "$HOME/.config/"*) copy_safe "$p" "$WORK/config/" ;;
          "$HOME/.local/share/fonts") copy_safe "$p" "$WORK/fonts/" ;;
          "$HOME/.zshrc"|"$HOME/.p10k.zsh"|"$HOME/.oh-my-zsh") copy_safe "$p" "$WORK/home/" ;;
          "$HOME/bin"|"$HOME/.local/bin") copy_safe "$p" "$WORK/" ;;
          *) copy_safe "$p" "$WORK/" ;;
        esac
      fi
      ((idx++))
    done
    idx=1
  done <<< "$pick"

  # Passwort abfragen + bestätigen (AES-256)
  local PASS1 PASS2
  PASS1=$(dialog --insecure --passwordbox "Enter password for encrypted backup (AES-256):" 10 60 3>&1 1>&2 2>&3)
  [ $? -ne 0 ] && pause_msg "Backup canceled." && rm -rf "$WORK" && return
  PASS2=$(dialog --insecure --passwordbox "Confirm password:" 10 60 3>&1 1>&2 2>&3)
  if [ "$PASS1" != "$PASS2" ]; then
    pause_msg "⚠️  Passwords do not match."
    rm -rf "$WORK"
    return
  fi

  dialog --infobox "🗜 Creating AES-256 encrypted, split archive..." 5 70
  sleep 0.3

  # Archiv erstellen (AES-256 mit -e) + Split in $SPLIT_SIZE
  (
    cd "$WORK" || exit 1
    # -e aktiviert AES-Verschlüsselung; -P übergibt das Passwort; -s splittet
    zip -r -e -P "$PASS1" -s "$SPLIT_SIZE" "$BACKUP_DIR/$BASENAME.zip" . >/dev/null 2>&1
  )
  local RC=$?

  rm -rf "$WORK"

  if [ $RC -ne 0 ]; then
    pause_msg "❌ Backup failed.\nCheck permissions and free space."
  else
    local parts
    parts=$(list_parts "$BACKUP_DIR/$BASENAME")
    pause_msg "✅ Encrypted, split backup created:\n\n$parts"
  fi
}

# ── RESTORE ───────────────────────────────────────────────────
restore_backup() {
  ensure_deps
  local FILE
  FILE=$(dialog --stdout --fselect "$BACKUP_DIR/" 15 80)
  [ -z "$FILE" ] && pause_msg "Restore canceled." && return

  case "$FILE" in
    *.zip) ;; # ok
    *) pause_msg "⚠️  Please select the .zip file (not .z01). The .z0N parts must be in the same folder." && return ;;
  esac

  local PASS
  PASS=$(dialog --insecure --passwordbox "Enter password to decrypt backup:" 10 60 3>&1 1>&2 2>&3)
  [ $? -ne 0 ] && pause_msg "Restore canceled." && return

  dialog --infobox "📂 Decrypting & extracting archive..." 5 70
  sleep 0.3

  local RESTORE_TMP
  RESTORE_TMP="$TMP_DIR/restore"
  rm -rf "$RESTORE_TMP"
  mkdir -p "$RESTORE_TMP"

  # unzip erkennt automatisch .z01/.z02… wenn die .zip ausgewählt wurde
  unzip -P "$PASS" -q "$FILE" -d "$RESTORE_TMP"
  if [ $? -ne 0 ]; then
    rm -rf "$RESTORE_TMP"
    pause_msg "❌ Wrong password or corrupted archive."
    return
  fi

  dialog --infobox "♻️ Copying files back to your system..." 5 70
  sleep 0.3

  # Zurückspielen
  mkdir -p "$HOME/.config" "$HOME/.local/share/fonts" "$HOME/bin" "$HOME/.local/bin"
  cp -a "$RESTORE_TMP/config/." "$HOME/.config/" 2>/dev/null
  cp -a "$RESTORE_TMP/home/." "$HOME/" 2>/dev/null
  cp -a "$RESTORE_TMP/fonts/." "$HOME/.local/share/fonts/" 2>/dev/null
  cp -a "$RESTORE_TMP/bin/." "$HOME/bin/" 2>/dev/null
  cp -a "$RESTORE_TMP/local/bin/." "$HOME/.local/bin/" 2>/dev/null
  fc-cache -fv >/dev/null 2>&1

  rm -rf "$RESTORE_TMP"
  pause_msg "✅ Encrypted split-backup successfully restored."
}

# ── MENU ──────────────────────────────────────────────────────
main_menu() {
  ensure_deps
  while true; do
    CHOICE=$(dialog --clear --backtitle "🔐 Desktop Backup Tool – AES-256 + Split" \
      --title "Main Menu" \
      --menu "Choose an action:" 15 70 5 \
      1 "Create encrypted split backup" \
      2 "Restore encrypted backup" \
      3 "Show backup folder" \
      4 "Exit" \
      3>&1 1>&2 2>&3)

    case "$CHOICE" in
      1) create_backup ;;
      2) restore_backup ;;
      3) pause_msg "Backup folder:\n$BACKUP_DIR" ;;
      4|*) clear; exit 0 ;;
    esac
  done
}

# ── START ─────────────────────────────────────────────────────
main_menu
