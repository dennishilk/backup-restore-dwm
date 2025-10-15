> ⚡ Your entire DWM desktop — rebuilt, restored, and optimized in minutes.
> 
# 🧩 backup-restore-dwm

**Author:** Dennis Hilk  
**Tested on:** Debian 13 Minimal  
**License:** MIT  

A complete one-click backup and restore solution for your custom DWM desktop setup.  
Perfect for rebuilding your system after a fresh install — or cloning your perfect setup across multiple machines.

---

## 🚀 Features

| Category | Description |
|-----------|-------------|
| 🧱 DWM | Builds your own source from `~/.config/suckless/dwm` |
| 🧩 Extras | Installs Dunst, Rofi, Picom, sxhkd, Kitty, ZSH, Oh-My-Zsh, Powerlevel10k |
| 🧊 ZRAM | Automatically enabled (zstd, 50 %) |
| 🔊 Soundfix | Select a local `soundfix.sh` to add to `autostart.sh` |
| 🔐 Backup | AES-256 encrypted, split archives (< 100 MB per part) |
| 🧠 Restore | Detects any backup name + parts `.z01/.z02/.zip` automatically |
| 🖼 Wallpaper | Adds feh hook for `~/.config/suckless/wallpapers/1.png` |
| ⚙️ Deps | Automatically installs `dialog`, `zip`, `unzip`, `feh`, build tools |

## ⚙️ want my full setup ?
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.zip
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z01
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z02
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z03
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z04
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z05
> 
> wget https://github.com/dennishilk/backup-restore-dwm/releases/download/v1.0.0/backup.z06

---

## 🧰 Dependencies

| Package | Purpose |
|----------|----------|
| `dialog` | Text-based menu interface |
| `git`, `curl`, `make`, `gcc`, `build-essential` | Build environment for Suckless tools |
| `xorg`, `xinit`, `feh`, `picom` | X11 desktop environment |
| `zsh`, `fonts-powerline` | Shell + Powerlevel10k |
| `rofi`, `dunst`, `sxhkd`, `kitty` | Desktop utilities |
| *(optional)* `nvidia-driver`, `firmware-amd-graphics`, `xserver-xorg-video-intel` | GPU drivers |
| *(optional)* `zram-tools`, `liquorix kernel` | Performance tuning |
| *(optional)* `zip`, `unzip` | Required for encrypted backups |
---

## 🚀 Installation

```bash
sudo apt install dialog git curl unzip -y
mkdir -p ~/.local/bin
cd ~/.local/bin
wget https://raw.githubusercontent.com/dennishilk/backup-restore-dwm/main/backup-restore.sh
chmod +x backup-restore.sh

