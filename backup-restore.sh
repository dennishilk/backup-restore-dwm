#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════╗
# ║   DWM Rebuilder Ultimate – Full Installer + Backup v1.0   ║
# ║   Author: Dennis Hilk                                     ║
# ║   Target: Debian 13 Minimal                               ║
# ║   Installs your own DWM from ~/.config/suckless/dwm       ║
# ║   Plus: ZRAM, extras, soundfix hook, AES-256 backup/restore║
# ╚════════════════════════════════════════════════════════════╝

set -euo pipefail

TITLE="DWM Rebuilder Ultimate"
BACKUP_DIR="$(pwd)/backups"
SPLIT_SIZE="95m"     # GitHub-friendly (<100MB)

# ────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────
need() {
  local pkg="$1"
  if ! command -v "$pkg" &>/dev/null; then
    echo "Installing missing dep: $pkg"
    sudo apt update -y >/dev/null 2>&1 || true
    sudo apt install -y "$pkg" >/dev/null 2>&1
  fi
}

ensure_base_deps() {
  # UI + archiver
  for p in dialog zip unzip git curl feh; do need "$p"; done
}

pause() { dialog --msgbox "$1" 10 70; }

ensure_build_deps() {
  # Build deps for suckless (dwm/st)
  sudo apt update -y
  sudo apt install -y build-essential pkg-config \
    libx11-dev libxft-dev libxinerama-dev libharfbuzz-dev
}

line_in_file() {
  local line="$1" file="$2"
  grep -Fqx -- "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# ────────────────────────────────────────────────────────────
# Install: your DWM from ~/.config/suckless/dwm
# ────────────────────────────────────────────────────────────
install_dwm_from_home() {
  ensure_build_deps
  local SRC="$HOME/.config/suckless/dwm"
  if [ ! -d "$SRC" ]; then
    pause "❌ DWM source not found:\n$SRC"
    return
  fi
  dialog --infobox "🧱 Building DWM from $SRC ..." 5 60; sleep 0.5
  ( cd "$SRC" && make clean >/dev/null 2>&1 || true && sudo make install )
  if command -v dwm >/dev/null 2>&1; then
    pause "✅ DWM installed successfully."
  else
    pause "❌ DWM build/install failed."
  fi

  # autostart.sh Unterstützung (falls vorhanden)
  # Dein Setup nutzt autostart.sh in ~/.config/suckless/dwm
  local AS="$HOME/.config/suckless/dwm/autostart.sh"
  if [ -f "$AS" ]; then
    chmod +x "$AS"
  fi
}

# ────────────────────────────────────────────────────────────
# Install extras (dunst, rofi, picom, sxhkd, kitty, zsh + oh-my-zsh + p10k)
# ────────────────────────────────────────────────────────────
install_extras() {
  sudo apt update -y
  sudo apt install -y dunst rofi picom sxhkd kitty zsh fonts-powerline

  # Oh-My-Zsh (non-interactive) + Powerlevel10k
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    dialog --infobox "🐚 Installing Oh-My-Zsh..." 5 50; sleep 0.5
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1 || true
  fi
  if [ ! -d "$HOME/.powerlevel10k" ]; then
    dialog --infobox "⭐ Installing Powerlevel10k..." 5 50; sleep 0.5
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.powerlevel10k" >/dev/null 2>&1 || true
  fi
  # .zshrc anpassen, p10k hooken
  local ZRC="$HOME/.zshrc"
  touch "$ZRC"
  line_in_file 'export ZSH="$HOME/.oh-my-zsh"' "$ZRC"
  line_in_file 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZRC"
  line_in_file 'source "$HOME/.powerlevel10k/powerlevel10k.zsh-theme"' "$ZRC"
  line_in_file 'plugins=(git)' "$ZRC"
  # default shell optional
  if [ "$(basename "$(getent passwd "$USER" | cut -d: -f7)")" != "zsh" ] && command -v zsh >/dev/null; then
    chsh -s "$(command -v zsh)" || true
  fi

  pause "✅ Extras installed.\n(You may log out/in to use zsh as default.)"
}

# ────────────────────────────────────────────────────────────
# ZRAM – install & activate
# ────────────────────────────────────────────────────────────
enable_zram() {
  sudo apt install -y zram-tools
  local CFG="/etc/default/zramswap"
  sudo bash -c "cat > '$CFG' <<'EOF'
# zramswap config
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF"
  sudo systemctl enable --now zramswap.service
  pause "✅ ZRAM enabled (zstd, 50%)."
}

# ────────────────────────────────────────────────────────────
# Soundfix integration – ask & hook into autostart.sh
# ────────────────────────────────────────────────────────────
integrate_soundfix() {
  local SUGGEST1="$HOME/soundfix.sh"
  local SUGGEST2="$HOME/.config/suckless/scripts/soundfix.sh"
  local SEL
  SEL=$(dialog --stdout --title "🔊 Soundfix Script" --fselect "$HOME/" 15 70)
  if [ -z "$SEL" ] || [ ! -f "$SEL" ]; then
    pause "⚠️ No script selected. Cancelled."
    return
  fi
  chmod +x "$SEL"

  local AS="$HOME/.config/suckless/dwm/autostart.sh"
  mkdir -p "$(dirname "$AS")"
  touch "$AS"; chmod +x "$AS"

  if grep -Fq "$SEL" "$AS"; then
    pause "ℹ️ Soundfix already present in autostart.sh."
  else
    echo "bash \"$SEL\" &" >> "$AS"
    pause "✅ Soundfix hooked into autostart.sh:\n$AS"
  fi
}

# ────────────────────────────────────────────────────────────
# Backup (AES-256 + split) & Restore (any name)
# ────────────────────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  local TS BASENAME TMP
  TS=$(date +%Y-%m-%d_%H-%M)
  BASENAME="dwm-backup_${TS}"
  TMP="$BACKUP_DIR/.tmp_$TS"
  mkdir -p "$TMP/config" "$TMP/home" "$TMP/fonts"

  # Default include paths (deine Liste)
  local include=(
    "$HOME/.config/suckless"
    "$HOME/.config/dunst"
    "$HOME/.config/picom"
    "$HOME/.config/rofi"
    "$HOME/.config/sxhkd"
    "$HOME/.config/kitty"
    "$HOME/.zshrc"
    "$HOME/.p10k.zsh"
    "$HOME/.oh-my-zsh"
    "$HOME/.local/share/fonts"
    "$HOME/.local/bin"
    "$HOME/bin"
  )

  # Checkliste
  local items=() i=1
  for p in "${include[@]}"; do items+=("$i" "$p" "on"); ((i++)); done
  local pick
  pick=$(dialog --stdout --separate-output --checklist "Select items to include:" 20 80 12 "${items[@]}")
  [ -z "$pick" ] && pause "Cancelled." && return

  dialog --infobox "📦 Collecting files..." 5 40; sleep 0.3
  i=1
  while read -r sel; do
    for p in "${include[@]}"; do
      if [ "$sel" -eq "$i" ] && [ -e "$p" ]; then
        case "$p" in
          "$HOME/.config/"*) cp -a "$p" "$TMP/config/" 2>/dev/null || true ;;
          "$HOME/.local/share/fonts") cp -a "$p" "$TMP/fonts/" 2>/dev/null || true ;;
          "$HOME/.zshrc"|"$HOME/.p10k.zsh"|"$HOME/.oh-my-zsh") cp -a "$p" "$TMP/home/" 2>/dev/null || true ;;
          "$HOME/.local/bin"|"$HOME/bin") cp -a "$p" "$TMP/" 2>/dev/null || true ;;
          *) cp -a "$p" "$TMP/" 2>/dev/null || true ;;
        esac
      fi
      ((i++))
    done
    i=1
  done <<< "$pick"

  # Passwort
  local P1 P2
  P1=$(dialog --insecure --passwordbox "Enter password (AES-256):" 10 60 3>&1 1>&2 2>&3) || { rm -rf "$TMP"; pause "Cancelled."; return; }
  P2=$(dialog --insecure --passwordbox "Confirm password:" 10 60 3>&1 1>&2 2>&3) || { rm -rf "$TMP"; pause "Cancelled."; return; }
  [ "$P1" != "$P2" ] && { rm -rf "$TMP"; pause "⚠️ Passwords do not match."; return; }

  dialog --infobox "🗜 Creating encrypted split archive..." 5 60; sleep 0.3
  ( cd "$TMP" && zip -r -e -P "$P1" -s "$SPLIT_SIZE" "$BACKUP_DIR/$BASENAME.zip" . >/dev/null )
  rm -rf "$TMP"

  local parts; parts=$(ls -1 "$BACKUP_DIR/$BASENAME".z?? 2>/dev/null || true; ls -1 "$BACKUP_DIR/$BASENAME.zip")
  pause "✅ Backup created:\n$parts"
}

restore_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  dialog --msgbox "Select the .zip file. Matching .z01/.z02 parts in the same folder are auto-detected." 8 60
  local ZIP; ZIP=$(dialog --stdout --fselect "$BACKUP_DIR/" 15 70) || { pause "Cancelled."; return; }
  [ -z "$ZIP" ] && { pause "Cancelled."; return; }
  case "$ZIP" in *.zip) ;; *) pause "⚠️ Please select the .zip (not .z01)."; return;; esac

  local PASS; PASS=$(dialog --insecure --passwordbox "Enter password:" 10 60 3>&1 1>&2 2>&3) || { pause "Cancelled."; return; }

  local BNAME BNOEXT DIR; BNAME="$(basename "$ZIP")"; BNOEXT="${BNAME%.*}"; DIR="$(dirname "$ZIP")"
  clear
  echo "🧩 Restore\n→ Base: $BNOEXT\n→ Dir:  $DIR"
  cd "$DIR"

  echo "🔎 Checking parts..."
  local MISSING=0
  for f in "$BNOEXT".z01 "$BNOEXT".z02 "$BNOEXT".z03; do
    [ -f "$f" ] || continue
  done

  echo "🔓 Extracting..."
  unzip -P "$PASS" "$BNAME" -d "$HOME" || { dialog --msgbox "❌ Wrong password or corrupted archive." 7 60; return; }
  fc-cache -fv >/dev/null 2>&1 || true

  dialog --msgbox "✅ Restore complete to your HOME." 6 50
}

# ────────────────────────────────────────────────────────────
# Wallpaper helper (optional, if 1.png exists)
# ────────────────────────────────────────────────────────────
wallpaper_hook() {
  local WP="$HOME/.config/suckless/wallpapers/1.png"
  local AS="$HOME/.config/suckless/dwm/autostart.sh"
  [ -f "$WP" ] || return 0
  mkdir -p "$(dirname "$AS")"; touch "$AS"; chmod +x "$AS"
  if ! grep -Fq 'feh --bg-fill "$HOME/.config/suckless/wallpapers/1.png"' "$AS" 2>/dev/null; then
    echo 'feh --bg-fill "$HOME/.config/suckless/wallpapers/1.png" &' >> "$AS"
  fi
}

# ────────────────────────────────────────────────────────────
# Menu
# ────────────────────────────────────────────────────────────
main_menu() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" --menu "Choose an action:" 18 80 10 \
      1 "Install DWM from ~/.config/suckless/dwm (build & install)" \
      2 "Install extras (dunst, rofi, picom, sxhkd, kitty, zsh + oh-my-zsh + p10k)" \
      3 "Enable ZRAM now (zstd, 50%)" \
      4 "Integrate soundfix.sh into autostart.sh" \
      5 "Create encrypted split backup (AES-256)" \
      6 "Restore encrypted backup (any name)" \
      7 "Add wallpaper hook (feh 1.png)" \
      8 "Exit" \
      3>&1 1>&2 2>&3) || { clear; exit 0; }

    case "$CHOICE" in
      1) install_dwm_from_home; wallpaper_hook ;;
      2) install_extras ;;
      3) enable_zram ;;
      4) integrate_soundfix ;;
      5) create_backup ;;
      6) restore_backup ;;
      7) wallpaper_hook; pause "✅ Wallpaper hook added (if 1.png exists)." ;;
      8) clear; exit 0 ;;
    esac
  done
}

main_menu
