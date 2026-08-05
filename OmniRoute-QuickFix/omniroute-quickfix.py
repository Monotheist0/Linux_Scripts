#!/usr/bin/env python3
"""
OmniRoute Quick Grammar Fixer v2.1 (Triple Ctrl+C Trigger)
Runs in the background on Fedora Linux.

Triggers on 3x rapid Ctrl+C presses:
1. Reads clipboard text.
2. Loads credentials safely from local .env file.
3. Sends to local OmniRoute LLM API with model: auto/fast.
4. Polishes grammar while preserving voice, formatting, and technical accuracy.
5. Replaces clipboard text & plays a subtle chime + desktop notification.
"""

import os
import sys
import time
import json
import threading
import subprocess
import urllib.request
from pynput import keyboard

# --- Helper: Load .env file safely ---
def load_env():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    env_path = os.path.join(script_dir, ".env")
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip("'\""))

load_env()

# --- Configuration ---
OMNIROUTE_URL = os.environ.get("OMNIROUTE_API_BASE", "http://localhost:20128/v1/chat/completions")
OMNIROUTE_API_KEY = os.environ.get("OMNIROUTE_API_KEY", "")
MODEL_ID = os.environ.get("OMNIROUTE_MODEL", "auto/fast")

# Enhanced System Prompt for Professional Client Communication
SYSTEM_PROMPT = (
    "You are an expert professional editor. Fix grammar, spelling, punctuation, and phrasing errors in the provided text.\n"
    "Rules:\n"
    "- Keep the tone natural, human, clear, and professional.\n"
    "- Eliminate AI slop, fluff, corporate buzzwords, and unnatural stiff language.\n"
    "- PRESERVE all original line breaks, markdown, bullet points, code snippets, and key formatting.\n"
    "- Preserve the author's underlying voice and intent.\n"
    "- Return ONLY the polished text without any meta-commentary, intros, or surrounding quotes."
)

TIME_WINDOW_SEC = 1.0  # 3 presses within 1.0 second
REQUIRED_PRESSES = 3

# --- State Tracking ---
c_press_times = []
is_ctrl_pressed = False
is_processing = False
lock = threading.Lock()

def get_clipboard_text():
    """Reads text from system clipboard (Wayland and X11 support)."""
    session = os.environ.get("XDG_SESSION_TYPE", "").lower()
    if session == "wayland":
        try:
            res = subprocess.run(["wl-paste", "--no-newline"], capture_output=True, text=True, timeout=2)
            if res.returncode == 0 and res.stdout:
                return res.stdout
        except Exception:
            pass

    # Try xclip (X11 / XWayland)
    try:
        res = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout:
            return res.stdout
    except Exception:
        pass

    # Try xsel fallback
    try:
        res = subprocess.run(["xsel", "-b", "-o"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout:
            return res.stdout
    except Exception:
        pass

    return ""

def set_clipboard_text(text):
    """Puts text into system clipboard (Wayland and X11 support)."""
    session = os.environ.get("XDG_SESSION_TYPE", "").lower()
    if session == "wayland":
        try:
            p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE, text=True)
            p.communicate(input=text)
            return
        except Exception:
            pass

    try:
        p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE, text=True)
        p.communicate(input=text)
        return
    except Exception:
        pass

    try:
        p = subprocess.Popen(["xsel", "-b", "-i"], stdin=subprocess.PIPE, text=True)
        p.communicate(input=text)
        return
    except Exception:
        pass

def play_audio_chime():
    """Plays subtle sound effect when text is ready."""
    try:
        subprocess.run(["canberra-gtk-play", "-i", "message-new-instant"], check=False)
    except Exception:
        pass

def send_notification(title, message, icon="edit-paste"):
    """Displays Linux desktop notification."""
    try:
        subprocess.run(["notify-send", "-a", "OmniRoute QuickFix", "-i", icon, title, message], check=False)
    except Exception:
        pass

def fix_grammar_with_omniroute(text):
    """Sends text to local OmniRoute API and returns corrected text with low token consumption."""
    payload = {
        "model": MODEL_ID,
        "stream": False,
        "temperature": 0.3,      # Low temp for focused, deterministic editing
        "max_tokens": 1000,       # Prevents token overconsumption
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text}
        ]
    }
    headers = {
        "Content-Type": "application/json"
    }
    if OMNIROUTE_API_KEY:
        headers["Authorization"] = f"Bearer {OMNIROUTE_API_KEY}"

    req = urllib.request.Request(
        OMNIROUTE_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        corrected = data["choices"][0]["message"]["content"].strip()
        return corrected

def trigger_workflow():
    global is_processing
    with lock:
        if is_processing:
            return
        is_processing = True

    def worker():
        global is_processing
        try:
            time.sleep(0.15)  # Wait for clipboard write to finalize
            text = get_clipboard_text()
            if not text or not text.strip():
                send_notification("OmniRoute QuickFix", "No text in clipboard to fix.", icon="dialog-warning")
                return

            send_notification("OmniRoute QuickFix", f"Fixing grammar ({MODEL_ID})...", icon="sync-synchronizing")

            fixed_text = fix_grammar_with_omniroute(text)
            set_clipboard_text(fixed_text)
            play_audio_chime()

            preview = (fixed_text[:55] + '...') if len(fixed_text) > 55 else fixed_text
            send_notification("OmniRoute QuickFix", f"✨ Fixed! Ready to paste:\n\"{preview}\"", icon="edit-paste")
        except Exception as e:
            send_notification("OmniRoute Error", str(e), icon="dialog-error")
        finally:
            with lock:
                is_processing = False

    threading.Thread(target=worker, daemon=True).start()

def on_press(key):
    global is_ctrl_pressed, c_press_times

    if key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
        is_ctrl_pressed = True

    is_c_key = False
    if hasattr(key, 'char') and key.char:
        if key.char.lower() == 'c' or key.char == '\x03':
            is_c_key = True

    if is_ctrl_pressed and is_c_key:
        now = time.time()
        c_press_times = [t for t in c_press_times if now - t <= TIME_WINDOW_SEC]
        c_press_times.append(now)

        if len(c_press_times) >= REQUIRED_PRESSES:
            c_press_times.clear()
            trigger_workflow()

def on_release(key):
    global is_ctrl_pressed
    if key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
        is_ctrl_pressed = False

def main():
    print("OmniRoute QuickFix Listener Running...")
    print(f"Endpoint: {OMNIROUTE_URL} | Model: {MODEL_ID}")
    print("Triple Ctrl+C anywhere to fix grammar!")

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()

if __name__ == "__main__":
    main()
