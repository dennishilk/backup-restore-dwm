# 🧩 DWM Encrypted Backup & Restore Tool 

**Author:** Dennis Hilk  
**Version:** 1.0  
**License:** MIT  
**Release Date:** 2025-10-15 

---

## 🧠 Overview

The **DWM Backup & Restore Tool v4.1** is a clean, nerd-approved shell utility  
for creating **AES-256-encrypted system backups** of your Linux desktop environment.

Supports both **single ZIP archives** and **split archives (100 MB chunks)**  
for easy GitHub uploads or NAS storage.

Built for 🐧 **Debian 13 Minimal** and fully compatible with your  
DWM + Rofi + ZSH + Powerlevel10k setup.

---

## 🔒 Features

| 🧩 Feature | 🧠 Description |
|------------|----------------|
| 🔐 **AES-256 Encryption** | Secure password-protected backups using `zip -e` |
| 🧱 **Split or Single Mode** | Choose between one big file or multiple 100 MB chunks |
| 🧮 **Automatic Verification** | Integrity check after backup (SHA256 + `unzip -t`) |
| 🧰 **Multi-config Backup** | Includes DWM, Rofi, sxhkd, Kitty, Dunst, Picom, Slstatus, ZSH |
| 🧾 **Nerd Status UI** | ASCII-style dialog output with icons and checksums |
| 🧩 **Smart Restore** | Auto-detects backups in `./backups` or script folder |
| 💬 **Error Handling** | Detects wrong passwords or missing split parts |
| 🧠 **100 % Offline** | No external API calls — pure bash and dialog magic |

🧾 Menu Overview
1. 🔒 Create encrypted backup (AES-256)
2. 🔐 Restore encrypted backup
3. ❌ Exit

📦 Backup Options

1) Single AES-256 ZIP (one large file)
2) Split into 100 MB chunks (GitHub-friendly)

---

## ⚙️ Dependencies

The tool installs missing packages automatically:

```bash
sudo apt install dialog zip unzip sha256sum
