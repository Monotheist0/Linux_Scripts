# 🚀 OmniRoute QuickFix (3x Ctrl+C Grammar Fixer)

A background productivity daemon for **Fedora Linux** (and Linux desktops) that monitors rapid `Ctrl+C` keypresses to automatically polish highlighted text using your local [OmniRoute](http://localhost:20128) LLM server.

*Credit: The rapid triple `Ctrl+C` trigger workflow was directly inspired by [PasteAI](https://pasteai.app/).*

---

## ✨ Features

- **Instant Trigger**: Highlight any text and press **`Ctrl + C` 3 times in 1 second**.
- **Model**: `auto/fast` for minimal latency.
- **Natural Voice Prompt**: Fixes typos, grammar, and syntax while removing AI slop and preserving your original tone, code blocks, and markdown structure.
- **Desktop Feedback**: Plays a subtle audio chime (`canberra-gtk-play`) and displays a preview toast notification (`notify-send`).
- **Instant Paste**: Replaces your clipboard content automatically so **`Ctrl + V`** immediately pastes the polished version.
- **Wayland & X11 Compatible**: Native support for `wl-copy`/`wl-paste` and `xclip`/`xsel`.

---

## 📁 Installation & Paths

- **Main Script**: `~/Applications/OmniRoute-QuickFix/omniroute-quickfix.py`
- **Systemd User Service**: `~/.config/systemd/user/omniroute-quickfix.service`
- **Desktop Autostart**: `~/.config/autostart/omniroute-quickfix.desktop`
- **OmniRoute Terminal Autostart**: `~/.config/autostart/omniroute-terminal.desktop`

---

## ⚙️ How to Manage the Service

### Start / Restart Service:
```bash
systemctl --user restart omniroute-quickfix
```

### Check Logs & Status:
```bash
systemctl --user status omniroute-quickfix
journalctl --user -u omniroute-quickfix -f
```

---

## 🧪 Manual Execution
```bash
python3 ~/Applications/OmniRoute-QuickFix/omniroute-quickfix.py
```
