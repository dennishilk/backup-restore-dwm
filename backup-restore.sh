#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║   DWM Rebuilder v2.0                                           ║
# ║   Author: Dennis Hilk                                          ║
# ║   Target: Debian 13 Minimal                                    ║
# ║   Features: DWM installer, backup/restore, ZRAM, soundfix      ║
# ╚════════════════════════════════════════════════════════════════╝

set -euo pipefail

TITLE="DWM Rebuilder Ultimate"
BACKUP_DIR="$(pwd)/backups"
SPLIT_SIZE="95m"

# ────────────────────────────────────────────────────────────────
# Helper functions
# ────────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || sudo apt install -y "$1"; }
pause() { dialog --msgbox "$1" 10 70; }

ensure_base_deps() {
  sudo apt update -y
  for p in dialog zip unzip wget git curl feh; do need "$p"; done
}

ensure_build_deps() {
  sudo apt install -y build-essential pkg-config \
    libx11-dev libxft-dev libxinerama-dev libharfbuzz-dev
}

# ────────────────────────────────────────────────────────────────
# Install official suckless tools (dwm, st, dmenu, slstatus)
# ────────────────────────────────────────────────────────────────
install_official_suckless() {
  ensure_build_deps
  local BASE="$HOME/.config/suckless"
  mkdir -p "$BASE"
  cd "$BASE" || exit 1

  declare -A TOOLS=(
    ["dwm"]="https://dl.suckless.org/dwm/dwm-6.5.tar.gz"
    ["st"]="https://dl.suckless.org/st/st-0.9.2.tar.gz"
    ["dmenu"]="https://dl.suckless.org/tools/dmenu-5.2.tar.gz"
    ["slstatus"]="https://github.com/drkhsh/slstatus/archive/refs/tags/1.0.tar.gz"
  )

  for TOOL in "${!TOOLS[@]}"; do
    local URL="${TOOLS[$TOOL]}"
    local TAR="/tmp/${TOOL}.tar.gz"
    dialog --infobox "⬇️ Downloading $TOOL..." 5 50
    wget -q -O "$TAR" "$URL" || { pause "⚠️ Failed to download $TOOL"; continue; }
    rm -rf "$BASE/$TOOL"
    mkdir -p "$BASE/$TOOL"
    tar -xzf "$TAR" --strip-components=1 -C "$BASE/$TOOL"
    dialog --infobox "🧱 Building $TOOL..." 5 40
    (cd "$BASE/$TOOL" && make clean >/dev/null 2>&1 || true && sudo make install >/dev/null 2>&1)
  done

  local MSG="🎉 Official Suckless tools installed:\n"
  for CMD in dwm st dmenu slstatus; do
    if command -v "$CMD" >/dev/null 2>&1; then MSG+="✅ $CMD\n"; else MSG+="⚠️ $CMD failed\n"; fi
  done

  # Wallpaper autostart
  local WALLPAPER="$HOME/.config/suckless/wallpapers/1.png"
  local AUTOSTART="$HOME/.config/suckless/dwm/autostart.sh"
  mkdir -p "$(dirname "$AUTOSTART")"; touch "$AUTOSTART"; chmod +x "$AUTOSTART"
  if [ -f "$WALLPAPER" ] && ! grep -Fq "feh --bg-fill" "$AUTOSTART"; then
    echo "feh --bg-fill \"$WALLPAPER\" &" >> "$AUTOSTART"
  fi

  pause "$MSG"
}

# ────────────────────────────────────────────────────────────────
# Install your own DWM from ~/.config/suckless/dwm
# ────────────────────────────────────────────────────────────────
install_dwm_from_home() {
  ensure_build_deps
  local SRC="$HOME/.config/suckless/dwm"
  local WALLPAPER="$HOME/.config/suckless/wallpapers/1.png"
  local AUTOSTART="$HOME/.config/suckless/dwm/autostart.sh"

  if [ ! -d "$SRC" ]; then
    dialog --yesno "❌ No DWM source found.\nClone from GitHub (dennishilk/dwm)?" 10 60
    if [ $? -eq 0 ]; then
      mkdir -p "$(dirname "$SRC")"
      git clone https://github.com/dennishilk/dwm "$SRC" || { pause "⚠️ Clone failed."; return; }
      pause "✅ DWM source cloned to:\n$SRC"
    else
      pause "Cancelled."; return
    fi
  fi

  dialog --infobox "🧱 Building DWM..." 5 40
  (cd "$SRC" && make clean >/dev/null 2>&1 || true && sudo make install >/dev/null 2>&1)

  if command -v dwm >/dev/null 2>&1; then
    pause "✅ DWM installed successfully!"
  else
    pause "❌ Build failed."; return
  fi

  mkdir -p "$(dirname "$AUTOSTART")"; touch "$AUTOSTART"; chmod +x "$AUTOSTART"
  if [ -f "$WALLPAPER" ] && ! grep -Fq "feh --bg-fill" "$AUTOSTART"; then
    echo "feh --bg-fill \"$WALLPAPER\" &" >> "$AUTOSTART"
  fi
  pause "🎉 DWM installation completed!"
}

# ────────────────────────────────────────────────────────────────
# Extras: Dunst, Picom, Rofi, sxhkd, Kitty, ZSH, Oh-My-Zsh, P10k
# ────────────────────────────────────────────────────────────────
install_extras() {
  sudo apt install -y dunst rofi picom sxhkd kitty zsh fonts-powerline
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1 || true
  fi
  if [ ! -d "$HOME/.powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.powerlevel10k" >/dev/null 2>&1 || true
  fi
  local ZRC="$HOME/.zshrc"
  echo 'export ZSH="$HOME/.oh-my-zsh"' > "$ZRC"
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZRC"
  echo 'plugins=(git)' >> "$ZRC"
  echo 'source $ZSH/oh-my-zsh.sh' >> "$ZRC"
  echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$ZRC"
  chsh -s "$(which zsh)" || true
  pause "✅ Extras installed successfully!"
}

# ────────────────────────────────────────────────────────────────
# ZRAM enable
# ────────────────────────────────────────────────────────────────
enable_zram() {
  sudo apt install -y zram-tools
  sudo bash -c 'cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF'
  sudo systemctl enable --now zramswap.service
  pause "✅ ZRAM enabled (zstd, 50%)."
}

# ────────────────────────────────────────────────────────────────
# Soundfix integration
# ────────────────────────────────────────────────────────────────
integrate_soundfix() {
  local SEL
  SEL=$(dialog --stdout --title "🔊 Select soundfix.sh" --fselect "$HOME/" 15 70)
  [ -z "$SEL" ] && pause "Cancelled." && return
  chmod +x "$SEL"
  local AUTOSTART="$HOME/.config/suckless/dwm/autostart.sh"
  mkdir -p "$(dirname "$AUTOSTART")"; touch "$AUTOSTART"; chmod +x "$AUTOSTART"
  if ! grep -Fq "$SEL" "$AUTOSTART"; then
    echo "bash \"$SEL\" &" >> "$AUTOSTART"
  fi
  pause "✅ Soundfix integrated into autostart.sh"
}

# ────────────────────────────────────────────────────────────────
# Backup (AES-256 encrypted split)
# ────────────────────────────────────────────────────────────────
create_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  local TS=$(date +%Y-%m-%d_%H-%M)
  local BASENAME="dwm-backup_$TS"
  local TMP="$BACKUP_DIR/.tmp_$TS"
  mkdir -p "$TMP"
  dialog --insecure --passwordbox "Enter password for encryption:" 10 60 2> /tmp/pw
  local PW=$(cat /tmp/pw); rm /tmp/pw
  dialog --infobox "📦 Creating encrypted split archive..." 5 60
  zip -r -e -P "$PW" -s "$SPLIT_SIZE" "$BACKUP_DIR/$BASENAME.zip" "$HOME/.config/suckless" "$HOME/.zshrc" "$HOME/.p10k.zsh" >/dev/null
  rm -rf "$TMP"
  pause "✅ Backup complete! Saved in $BACKUP_DIR/"
}

restore_backup() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  local ZIP=$(dialog --stdout --title "Select ZIP" --fselect "$BACKUP_DIR/" 15 70)
  [ -z "$ZIP" ] && pause "Cancelled." && return
  dialog --insecure --passwordbox "Enter decryption password:" 10 60 2> /tmp/pw
  local PW=$(cat /tmp/pw); rm /tmp/pw
  unzip -P "$PW" "$ZIP" -d "$HOME" >/dev/null || { pause "❌ Wrong password or corrupt file."; return; }
  pause "✅ Backup restored to $HOME"
}

# ────────────────────────────────────────────────────────────────
# Menu
# ────────────────────────────────────────────────────────────────
main_menu() {
  ensure_base_deps
  mkdir -p "$BACKUP_DIR"
  while true; do
    CHOICE=$(dialog --clear --backtitle "$TITLE" --title "Main Menu" --menu "Choose an action:" 20 80 10 \
      1 "Install official DWM + tools (st, dmenu, slstatus)" \
      2 "Install my DWM from ~/.config/suckless/dwm" \
      3 "Install extras (dunst, picom, rofi, sxhkd, kitty, zsh + oh-my-zsh + p10k)" \
      4 "Enable ZRAM (zstd, 50%)" \
      5 "Integrate soundfix.sh into autostart.sh" \
      6 "Create encrypted backup (AES-256)" \
      7 "Restore encrypted backup" \
      8 "Exit" \
      3>&1 1>&2 2>&3) || break

    case "$CHOICE" in
      1) install_official_suckless ;;
      2) install_dwm_from_home ;;
      3) install_extras ;;
      4) enable_zram ;;
      5) integrate_soundfix ;;
      6) create_backup ;;
      7) restore_backup ;;
      8) clear; exit 0 ;;
    esac
  done
}

main_menu
