#!/bin/bash
# ────────────────────────────────────────────────
# 🧩 backup & restore DWM
# Author: Dennis Hilk
# Year: 2025
# Works perfectly on Debian 13 Minimal
# https://github.com/dennishilk/backup-restore-dwm
# ────────────────────────────────────────────────

BACKUP_DIR="$HOME/Desktop-Backup"
mkdir -p "$BACKUP_DIR"

# ────────────────────────────────────────────────
# MAIN MENU
# ────────────────────────────────────────────────
main_menu() {
    CHOICE=$(dialog --clear --backtitle "🧩 Desktop Manager v8 – Ultimate Edition" \
        --title "Main Menu" \
        --menu "Select an option:" 15 60 4 \
        1 "Create Backup" \
        2 "Full System Install / Restore" \
        3 "Restore Only My Backup" \
        4 "Exit" \
        3>&1 1>&2 2>&3)

    case $CHOICE in
        1) create_backup ;;
        2) restore_full_system ;;
        3) restore_backup_basic ;;
        4) clear; exit 0 ;;
    esac
}

# ────────────────────────────────────────────────
# BACKUP CREATION
# ────────────────────────────────────────────────
create_backup() {
    DATE=$(date +%Y-%m-%d_%H-%M)
    ZIP_NAME="desktop-backup_${DATE}.zip"
    TMP_DIR="$BACKUP_DIR/tmp"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR/config" "$TMP_DIR/home" "$TMP_DIR/fonts"

    dialog --infobox "📦 Collecting files..." 5 40
    sleep 0.5

    cp -r ~/.config/suckless "$TMP_DIR/config/" 2>/dev/null
    cp -r ~/.config/{kitty,rofi,dunst,picom,sxhkd} "$TMP_DIR/config/" 2>/dev/null
    cp ~/.zshrc ~/.p10k.zsh "$TMP_DIR/home/" 2>/dev/null
    cp -r ~/.oh-my-zsh "$TMP_DIR/home/" 2>/dev/null
    cp -r ~/.local/share/fonts "$TMP_DIR/fonts/" 2>/dev/null
    cp -r ~/bin "$TMP_DIR/" 2>/dev/null
    cp -r ~/.local/bin "$TMP_DIR/" 2>/dev/null

    cd "$TMP_DIR" || exit
    zip -r "../$ZIP_NAME" * >/dev/null 2>&1
    cd ..
    rm -rf "$TMP_DIR"

    dialog --msgbox "✅ Backup created:\n$BACKUP_DIR/$ZIP_NAME" 10 60
    main_menu
}

# ────────────────────────────────────────────────
# RESTORE ONLY BACKUP (NO INSTALL)
# ────────────────────────────────────────────────
restore_backup_basic() {
    BACKUP_FILE=$(dialog --fselect "$BACKUP_DIR/" 15 70 3>&1 1>&2 2>&3)
    [ ! -f "$BACKUP_FILE" ] && dialog --msgbox "⚠️ File not found." 8 50 && main_menu

    TMP_RESTORE="/tmp/restore"
    rm -rf "$TMP_RESTORE"
    mkdir -p "$TMP_RESTORE"
    unzip -q "$BACKUP_FILE" -d "$TMP_RESTORE"

    cp -r "$TMP_RESTORE/config/"* ~/.config/ 2>/dev/null
    cp -r "$TMP_RESTORE/home/." ~ 2>/dev/null
    cp -r "$TMP_RESTORE/fonts/"* ~/.local/share/fonts/ 2>/dev/null
    cp -r "$TMP_RESTORE/bin/"* ~/bin/ 2>/dev/null
    cp -r "$TMP_RESTORE/local/bin/"* ~/.local/bin/ 2>/dev/null
    fc-cache -fv >/dev/null 2>&1

    dialog --msgbox "✅ Backup successfully restored!" 8 50
    main_menu
}

# ────────────────────────────────────────────────
# FULL SYSTEM RESTORE / INSTALL
# ────────────────────────────────────────────────
restore_full_system() {
    BACKUP_FILE=$(dialog --fselect "$BACKUP_DIR/" 15 70 3>&1 1>&2 2>&3)
    [ ! -f "$BACKUP_FILE" ] && dialog --msgbox "⚠️ File not found." 8 50 && main_menu

    dialog --infobox "📦 Installing base system packages..." 6 60
    sudo apt update -y >/dev/null 2>&1
    sudo apt install -y git make gcc build-essential \
      libx11-dev libxft-dev libxinerama-dev xorg xinit zsh unzip feh picom \
      rofi dunst sxhkd kitty dialog curl fonts-powerline >/dev/null 2>&1

    # ─── Liquorix Kernel ──────────────────────────
    dialog --yesno "⚙️ Do you want to install the Liquorix Kernel?" 8 60
    if [ $? -eq 0 ]; then
        dialog --infobox "💿 Installing Liquorix Kernel..." 5 50
        sudo apt install -y apt-transport-https curl >/dev/null 2>&1
        curl -fsSL https://liquorix.net/liquorix-keyring.gpg | sudo tee /usr/share/keyrings/liquorix-keyring.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian bookworm main" | sudo tee /etc/apt/sources.list.d/liquorix.list >/dev/null
        sudo apt update -y >/dev/null 2>&1
        sudo apt install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 >/dev/null 2>&1
        sudo update-grub >/dev/null 2>&1
    fi

    # ─── GPU Drivers ──────────────────────────────
    GPU=$(dialog --menu "Select your GPU:" 12 50 4 \
        1 "NVIDIA" 2 "AMD/ATI" 3 "Intel" 4 "Skip" \
        3>&1 1>&2 2>&3)
    case $GPU in
        1) sudo apt install -y nvidia-driver firmware-misc-nonfree >/dev/null 2>&1 ;;
        2) sudo apt install -y firmware-amd-graphics mesa-vulkan-drivers >/dev/null 2>&1 ;;
        3) sudo apt install -y xserver-xorg-video-intel mesa-utils >/dev/null 2>&1 ;;
    esac

    # ─── Unpack Backup ────────────────────────────
    TMP_RESTORE="/tmp/restore"
    rm -rf "$TMP_RESTORE"; mkdir -p "$TMP_RESTORE"
    unzip -q "$BACKUP_FILE" -d "$TMP_RESTORE"
    cp -r "$TMP_RESTORE/config/"* ~/.config/ 2>/dev/null
    cp -r "$TMP_RESTORE/home/." ~ 2>/dev/null
    cp -r "$TMP_RESTORE/fonts/"* ~/.local/share/fonts/ 2>/dev/null
    cp -r "$TMP_RESTORE/bin/"* ~/bin/ 2>/dev/null
    cp -r "$TMP_RESTORE/local/bin/"* ~/.local/bin/ 2>/dev/null
    fc-cache -fv >/dev/null 2>&1

    # ─── ZRAM Option ──────────────────────────────
    dialog --yesno "💾 Enable ZRAM (zram-tools)?" 8 40
    if [ $? -eq 0 ]; then
        sudo apt install -y zram-tools >/dev/null 2>&1
        echo "ALGO=lz4" | sudo tee /etc/default/zramswap >/dev/null
        echo "PERCENT=100" | sudo tee -a /etc/default/zramswap >/dev/null
        sudo systemctl enable --now zramswap >/dev/null 2>&1
    fi

    # ─── Soundfix Option ──────────────────────────
    dialog --yesno "🔊 Enable SPDIF Soundfix Tool?" 8 50
    if [ $? -eq 0 ]; then
        mkdir -p ~/.local/bin
        cat << 'EOF' > ~/.local/bin/spdif-fix.sh
#!/bin/bash
# SPDIF Delay Fix by Dennis Hilk
pw-cli s 0 node.name "SPDIF-Output"
pw-metadata -n settings 0 clock.force-rate 48000
EOF
        chmod +x ~/.local/bin/spdif-fix.sh
    fi

    # ─── Suckless Tools ───────────────────────────
    dialog --infobox "🧱 Installing / building DWM, ST, SLStatus..." 6 50
    mkdir -p ~/.config/suckless
    cd ~/.config/suckless || exit
    [ ! -d dwm ] && git clone https://git.suckless.org/dwm
    [ ! -d st ] && git clone https://git.suckless.org/st
    [ ! -d slstatus ] && git clone https://git.suckless.org/slstatus
    cd dwm && sudo make clean install && cd ..
    cd st && sudo make clean install && cd ..
    cd slstatus && sudo make clean install && cd ~

    # ─── ZSH + Oh-My-Zsh ──────────────────────────
    dialog --infobox "🐚 Setting up ZSH + Oh-My-Zsh..." 6 50
    if [ ! -d ~/.oh-my-zsh ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    chsh -s $(which zsh)

    # ─── Create .xinitrc ──────────────────────────
    cat << 'EOF' > ~/.xinitrc
#!/bin/bash
picom &
if [ -f ~/.config/suckless/wallpapers/1.png ]; then
  feh --bg-scale ~/.config/suckless/wallpapers/1.png &
fi
[ -f ~/.local/bin/spdif-fix.sh ] && ~/.local/bin/spdif-fix.sh &
exec dwm
EOF
    chmod +x ~/.xinitrc

    dialog --msgbox "✅ Full installation complete!\nRun 'startx' to launch DWM." 10 60
    clear
}

# ────────────────────────────────────────────────
# START
# ────────────────────────────────────────────────
clear
main_menu
