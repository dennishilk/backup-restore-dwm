> ⚡ Your entire DWM desktop — rebuilt, restored, and optimized in minutes.
> 
# 🧩 backup-restore-dwm

**Author:** Dennis Hilk  
**Tested on:** Debian 13 Minimal  
**License:** MIT  

A complete one-click backup and restore solution for your custom DWM desktop setup.  
Perfect for rebuilding your system after a fresh install — or cloning your perfect setup across multiple machines.

---

## ✨ Features

- 🧱 **Full Debian 13 Minimal setup**  
  Installs all base X11 + build dependencies  
  Optional **Liquorix kernel** installation  

- 🎮 **GPU Driver Installer**  
  Choose NVIDIA / AMD / Intel  

- 💾 **ZRAM activation**  
  Enables `zram-tools` for fast memory compression  

- 🔊 **SPDIF Soundfix Tool**  
  Fixes digital audio delay in PipeWire setups  

- 🐧 **Suckless stack**  
  Auto-installs and builds `dwm`, `st`, and `slstatus`  

- 🧠 **ZSH + Oh-My-Zsh + Powerlevel10k**  
  Full shell customization out of the box  

- 🌄 **Wallpaper support**  
  Automatically loads `1.png` from `~/.config/suckless/wallpapers/`  

- 🪶 **Backup & Restore**  
  One-click zip backup and restore of all configs, fonts, and scripts  

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

---

## 🚀 Installation

```bash
sudo apt install dialog git curl unzip -y
mkdir -p ~/.local/bin
cd ~/.local/bin
wget https://raw.githubusercontent.com/dennishilk/backup-restore-dwm/main/backup-restore.sh
chmod +x backup-restore.sh
