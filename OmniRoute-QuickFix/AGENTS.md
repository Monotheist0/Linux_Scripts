# 🤖 AGENTS.md — OmniRoute QuickFix Technical & Operational Context

This document serves as an agent-agnostic technical reference for AI agents (and human maintainers) working on or interacting with **OmniRoute QuickFix**.

---

## 🎯 Executive Overview

**OmniRoute QuickFix v3.4** is a lightweight background productivity daemon for Linux desktops (Fedora, Wayland/X11). It monitors global keyboard events for rapid keypress patterns:
1. **3x `Ctrl+C`**: Instantly corrects grammar, typos, and formatting using your local OmniRoute LLM server.
2. **1x `Ctrl+Shift+;`** (or **1x `Ctrl+;`**): Instantly pops up a keyboard-first GTK Zenity preset menu to select specialized prompts (**Summarize Papers/Articles**, **Professional Email**, **Translate to English**) or **Add/Delete Custom Prompts on the fly**.

Upon completion, it replaces the system clipboard content, plays an audio chime, and sends a desktop notification so the user can immediately paste (`Ctrl+V`) the polished text.

---

## 🏗️ Architecture & Component Breakdown

```
 +-----------------------------------------------------------+
 | 3x Ctrl+C (Instant Grammar) OR 1x Ctrl+Shift+; (Menu)     |
 +-----------------------------------------------------------+
                               |
                      pynput Keyboard Listener
                               v
                 +----------------------------+
                 |   omniroute-quickfix.py    |
                 +----------------------------+
                  /                          \
 1x Ctrl+Shift+; /                            \ 3x Ctrl+C
                v                              v
    +------------------------+      +--------------------+
    | Zenity GTK Preset Menu |      |  Grammar Fix Preset|
    | (Keyboard-First Enter) |      +--------------------+
    +------------------------+                 |
         |           \                         |
 ➕ Add / 🗑️ Delete   \                       |
         v             v                     v
   [prompts.json]   1. Grab Clipboard (wl-paste / xclip)
                    2. HTTP POST to OmniRoute (max_tokens=4096, timeout=45s)
                    3. Replace Clipboard (wl-copy / xclip)
                    4. Play Chime (canberra-gtk-play) & Notify (notify-send)
                                        v
                            +-----------------------+
                            |  Ready to Ctrl+V      |
                            +-----------------------+
```

### Key Components

1. **Daemon Listener (`omniroute-quickfix.py`)**:
   - Built on `pynput.keyboard.Listener`.
   - `3x Ctrl+C`: Instant Grammar Fix.
   - `1x Ctrl+Shift+;` or `1x Ctrl+;`: Immediate Zenity Menu popup.
   - Thread-safe execution (`threading.Lock`) prevents overlapping API calls.

2. **Keyboard-First Zenity Preset Menu & Dynamic Management**:
   - Uses GTK row activation: **`↑ / ↓` Arrow Keys + `Enter`** immediately selects and executes without requiring any mouse interaction.
   - Reads/writes presets dynamically from [`prompts.json`](file:///mnt/Shared/Projects/Github/Linux_Scripts/OmniRoute-QuickFix/prompts.json).
   - Built-in GUI options to **➕ Add New Preset Prompt** and **🗑️ Delete Preset Prompt** without touching any code.

3. **Clipboard & LLM Client**:
   - Wayland (`wl-paste`/`wl-copy`) and X11 (`xclip`/`xsel`) support.
   - Max output tokens set to **`4096`** with a 45-second timeout to handle long articles and research papers.
   - Natural LLM sampling without hardcoded temperature forcing.

4. **Desktop UI / Notifications**:
   - **Audio Chime**: `canberra-gtk-play -i message-new-instant`
   - **Toast Notification**: `notify-send -a "OmniRoute QuickFix"` with preview text.

---

## ⚙️ Environment Configuration (`.env`)

Loaded dynamically on startup relative to the script location:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `OMNIROUTE_API_BASE` | `http://localhost:20128/v1/chat/completions` | Local OmniRoute LLM proxy base URL |
| `OMNIROUTE_API_KEY` | *(optional)* | Bearer auth key for OmniRoute API |
| `OMNIROUTE_MODEL` | `auto/fast` | Target LLM model |
| `OMNIROUTE_MAX_TOKENS`| `4096` | Maximum token response limit |

---

## 🔄 System Integration & Autostart

### 1. Systemd User Service (`~/.config/systemd/user/omniroute-quickfix.service`)
```ini
[Unit]
Description=OmniRoute 3x Ctrl+C Quick Grammar Fixer
After=network.target graphical-session.target

[Service]
ExecStart=/usr/bin/python3 /mnt/Shared/Projects/Github/Linux_Scripts/OmniRoute-QuickFix/omniroute-quickfix.py
Restart=always
RestartSec=3
Environment=DISPLAY=:0
Environment=XDG_SESSION_TYPE=x11

[Install]
WantedBy=default.target
```

---

## 🛠️ Management Commands

```bash
# Check service status
systemctl --user status omniroute-quickfix

# Restart service after code edits
systemctl --user restart omniroute-quickfix

# Stream live log output
journalctl --user -u omniroute-quickfix -f

# Test manually in foreground
python3 /mnt/Shared/Projects/Github/Linux_Scripts/OmniRoute-QuickFix/omniroute-quickfix.py
```
