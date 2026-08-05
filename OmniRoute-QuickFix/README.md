# 🚀 OmniRoute QuickFix (Grammar Fixer & Preset Manager)

A background productivity daemon for **Fedora Linux** (and Linux desktops) that monitors rapid keyboard shortcuts to automatically polish text or run AI actions using your local [OmniRoute](http://localhost:20128) LLM server.

*Credit: The rapid triple keypress trigger workflow was directly inspired by [PasteAI](https://pasteai.app/).*

---

## ✨ Features

- **Instant Grammar Fix**: Highlight text and press **`Ctrl + C` 3 times in 1 second**.
- **Instant Action Preset Menu**: Press **`Ctrl + Shift + ;` 1 time** (or `Ctrl + ;`) to immediately pop up a GTK Zenity prompt selector:
  - 📝 **Grammar Fix**: Error & typo correction.
  - 📰 **Summarize (Bullets)**: Summarize long articles & research papers into 3–7 key takeaway bullet points.
  - ✉️ **Professional Email**: Polish tone to articulate & corporate.
  - 🌐 **Translate to English**: Fluent English translation.
  - ➕ **Add New Preset Prompt...**: Create custom prompt presets directly inside the GUI dialog.
  - 🗑️ **Delete a Preset Prompt...**: Remove presets on the fly.
- **JSON-Backed Presets**: Edit presets manually in [`prompts.json`](file:///mnt/Shared/Projects/Github/Linux_Scripts/OmniRoute-QuickFix/prompts.json) or manage them from the GUI.
- **Large Document Support**: Capped at **4,000 output tokens** and 45s HTTP timeout for long papers and web articles.
- **Desktop Feedback**: Subtle audio chime (`canberra-gtk-play`) and preview toast notification (`notify-send`).
- **Instant Paste**: Replaces your clipboard content automatically so **`Ctrl + V`** immediately pastes the result.

---

## 📁 Installation & Paths

- **Main Script**: `~/Applications/OmniRoute-QuickFix/omniroute-quickfix.py`
- **Presets Config**: `~/Applications/OmniRoute-QuickFix/prompts.json`
- **Systemd User Service**: `~/.config/systemd/user/omniroute-quickfix.service`
- **Desktop Autostart**: `~/.config/autostart/omniroute-quickfix.desktop`

---

## ⚙️ How to Manage the Service

```bash
# Start / Restart Service:
systemctl --user restart omniroute-quickfix

# Check Logs & Status:
systemctl --user status omniroute-quickfix
journalctl --user -u omniroute-quickfix -f
```
