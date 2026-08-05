# Linux Scripts Collection 🚀

Personal collection of Bash & Python scripts for Linux system administration, AI workflow automation, and productivity on Fedora Linux.

---

## 🛠️ Included Tools & Workflows

### 1. ⚡ OmniRoute QuickFix (`OmniRoute-QuickFix/`)
* **Description**: Background productivity daemon triggered by pressing **`Ctrl + C` 3 times in 1 second** on highlighted text.
* **Function**: Automatically sends copied text to your local [OmniRoute](http://localhost:20128) LLM server using the fast model (`auto/fast`), polishes grammar/tone without AI slop, and updates your clipboard ready for instant **`Ctrl + V`** pasting.
* **Features**: Audio chime feedback (`canberra-gtk-play`), desktop notifications (`notify-send`), systemd user service & desktop autostart.
* **Usage**:
  ```bash
  python3 OmniRoute-QuickFix/omniroute-quickfix.py
  ```

---

### 2. 📊 System Inventory Organiser (`System Inventory Organiser/`)
* **Description**: Comprehensive system auditing tool tailored for Fedora Linux (supports DNF5, DNF4, Flatpak, & Snap).
* **Function**: Scans installed applications, desktop entries, package repositories, storage/disk health, and hardware specs into a clean timestamped report.
* **Fixes & Status**: Fully tested and non-interactive safe (no blocking `sudo` prompts during storage/SMART health scans).
* **Usage**:
  ```bash
  cd "System Inventory Organiser"
  ./system_inventory.sh -u
  ```

---

## 📦 Installation & Setup

```bash
git clone https://github.com/Shoytanbaba99/Linux_Scripts.git
cd Linux_Scripts

# Make scripts executable
chmod +x "System Inventory Organiser/system_inventory.sh"
chmod +x "OmniRoute-QuickFix/omniroute-quickfix.py"
```

---

## 📜 License

Licensed under the **MIT License**.
Developed & maintained for Fedora Linux workflows. Feel free to use, modify, and share!
