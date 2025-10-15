# 🧩 DWM Encrypted Backup & Restore Tool (Minimal v2.0)

**Author:** Dennis Hilk  
**Version:** v2.0.0  
**Release Date:** 2025-10-17  

---

## 🧠 Overview

A simple and secure **AES-256 encrypted backup & restore tool** for your DWM setup or any configuration files.  
This minimal version includes **only** the essential backup and restore logic —  
no DWM installation, no extras, no dependencies beyond basic compression utilities.

Perfect for lightweight systems like **Debian 13 Minimal**.

---

## 🔒 Features

| Feature | Description |
|----------|-------------|
| 🔐 AES-256 Encryption | Password-protected backups using the `zip` AES algorithm |
| 📦 Split Archives | Automatically splits archives into <100 MB chunks (GitHub-friendly) |
| 🧩 Restore Detection | Finds backups automatically in `./backups` or the script directory |
| 🧠 Interactive Menu | Clean `dialog`-based TUI for backup and restore |
| 💾 Offline Ready | Works entirely offline after dependencies are installed |
| 🐧 Linux Native | Designed for Debian 13 Minimal and similar lightweight distros |

---

## ⚙️ Dependencies

The script automatically installs them if missing:

```bash
dialog zip unzip
