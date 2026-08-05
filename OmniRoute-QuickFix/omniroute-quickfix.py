#!/usr/bin/env python3
"""
OmniRoute Quick Fixer v3.4
Runs in the background on Fedora / Linux desktops.

Triggers:
- 3x rapid Ctrl+C: Instant default grammar fix.
- 1x Ctrl+Shift+; (or 1x Ctrl+;): Pops up Zenity preset menu immediately (Keyboard-First).

Features:
- Pure Keyboard Navigation: Arrow Up/Down + Enter instantly selects and executes!
- Full GUI management: Add, Edit, Delete preset prompts on the fly.
- Presets stored in `prompts.json` for easy editing.
"""

import os
import sys
import time
import json
import threading
import subprocess
import urllib.request
from pynput import keyboard

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
PROMPTS_FILE = os.path.join(SCRIPT_DIR, "prompts.json")

# --- Helper: Load .env file safely ---
def load_env():
    env_path = os.path.join(SCRIPT_DIR, ".env")
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
MAX_TOKENS = int(os.environ.get("OMNIROUTE_MAX_TOKENS", "4096"))

TIME_WINDOW_SEC = 1.0
REQUIRED_PRESSES = 3

# --- Prompt Storage (JSON-backed) ---
DEFAULT_PROMPTS = {
    "Grammar Fix": {
        "prompt": (
            "You are an expert text editor. Correct all spelling, typographical, and grammatical errors in the provided text. "
            "Strictly adhere to these constraints: Do not rephrase, restructure, or condense the text unless necessary for grammatical correctness. "
            "Preserve the original tone, sentence structure, meaning, code snippets, and markdown formatting exactly. "
            "Do not use em dashes, semicolons, or any stylistic flourishes. Do not include AI slop, conversational filler, introductory text, or concluding commentary. "
            "Output only the corrected text."
        ),
        "label": "Fixing grammar"
    },
    "Professional Email": {
        "prompt": (
            "You are a professional communications editor. Rewrite the following text to sound clear, articulate, professional, and polite, suitable for a corporate environment. "
            "Preserve the core message, intent, and factual information. Remove any aggressive, overly casual, or emotional language. "
            "Do not use em dashes, semicolons, or flowery adjectives. "
            "Do not include introductory text, explanations, or concluding commentary. Output only the rewritten text."
        ),
        "label": "Polishing tone"
    },
    "Obsidian Engineering Note": {
        "prompt": (
            "You are a technical knowledge curator and software engineering expert. Transform the raw note, text excerpt, or concept provided into a structured, clean Obsidian Permanent Note using the Feynman technique. "
            "Strictly follow this exact Markdown structure:\n\n"
            "# Concept: [Concept Name]\n\n"
            "**Definition**:\n"
            "[1–2 sentence clear textbook-style definition of the concept.]\n\n"
            "**Key Points**:\n"
            "- [Bullet point 1]\n"
            "- [Bullet point 2]\n\n"
            "**Example**:\n"
            "- ✅ **Good**: [Practical positive example or correct use-case]\n\n"
            "**Anti-Example**:\n"
            "- ❌ **Bad**: [Counter-example, common pitfall, or anti-pattern]\n\n"
            "**Related**:\n"
            "- [[Related Concept 1]]\n"
            "- [[Related Concept 2]]\n\n"
            "Constraints: Do not use em dashes or semicolons. Ensure all related topics use standard Obsidian [[WikiLink]] syntax. "
            "Output strictly the Markdown note formatted above with no introductory chatter, commentary, or wrapper text."
        ),
        "label": "Formatting Obsidian Note"
    },
    "Key Takeaways & Meaning": {
        "prompt": (
            "You are a high-efficiency information synthesizer. Analyze the provided text, article, or document and extract the core message. "
            "Strictly follow this exact output structure:\n\n"
            "**Core Takeaway**:\n"
            "[1–2 sentences stating the main conclusion or central point.]\n\n"
            "**What It Means**:\n"
            "[1–2 sentences explaining the practical impact, significance, or real-world application.]\n\n"
            "**Key Details**:\n"
            "- [Essential detail, supporting fact, or data point 1]\n"
            "- [Essential detail, supporting fact, or data point 2]\n"
            "- [Essential detail, supporting fact, or data point 3]\n\n"
            "Constraints: Do not use em dashes or semicolons. Do not include AI slop, conversational filler, introductory text, or concluding remarks. "
            "Output only the structured summary formatted above."
        ),
        "label": "Synthesizing takeaways"
    },
    "Extract Action Items": {
        "prompt": (
            "Analyze the provided meeting notes, email, or text block and extract all actionable tasks, deadlines, and responsibilities. "
            "Format the output as a checklist using markdown checkboxes (e.g., '- [ ] Task description'). "
            "Do not use em dashes or semicolons. "
            "Output only the checklist with no introductory text or conversational filler."
        ),
        "label": "Extracting tasks"
    },
    "Format as Markdown Table": {
        "prompt": (
            "Convert the provided unstructured text, list, or comma-separated data into a clean, properly aligned Markdown table. "
            "Infer the column headers logically based on the provided data if they are not explicitly stated. "
            "Do not include any introductory text, explanations, or conversational filler. Output only the Markdown table."
        ),
        "label": "Formatting table"
    }
}

def load_prompts():
    """Loads prompt presets from prompts.json."""
    if os.path.exists(PROMPTS_FILE):
        try:
            with open(PROMPTS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict) and data:
                    return data
        except Exception:
            pass
    save_prompts(DEFAULT_PROMPTS)
    return DEFAULT_PROMPTS.copy()

def save_prompts(prompts_dict):
    """Saves prompt presets to prompts.json."""
    try:
        with open(PROMPTS_FILE, "w", encoding="utf-8") as f:
            json.dump(prompts_dict, f, indent=2)
    except Exception as e:
        print(f"Error saving prompts: {e}")

# --- State Tracking ---
ctrl_c_press_times = []
is_ctrl_pressed = False
is_shift_pressed = False
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

    try:
        res = subprocess.run(["xclip", "-selection", "clipboard", "-o"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and res.stdout:
            return res.stdout
    except Exception:
        pass

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

def call_omniroute_api(text, system_prompt):
    """Sends text to local OmniRoute API."""
    payload = {
        "model": MODEL_ID,
        "stream": False,
        "max_tokens": MAX_TOKENS,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text}
        ]
    }
    headers = {"Content-Type": "application/json"}
    if OMNIROUTE_API_KEY:
        headers["Authorization"] = f"Bearer {OMNIROUTE_API_KEY}"

    req = urllib.request.Request(
        OMNIROUTE_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"].strip()

def add_new_preset():
    """Spawns Zenity entry boxes to add a new custom preset prompt."""
    env = os.environ.copy()
    
    # Step 1: Preset Name
    cmd_name = [
        "zenity", "--entry",
        "--title=Add New Preset",
        "--text=Enter a title for your new prompt preset (e.g. ELI5 / Spanish Translate):",
        "--entry-text="
    ]
    res_name = subprocess.run(cmd_name, capture_output=True, text=True, env=env)
    if res_name.returncode != 0 or not res_name.stdout.strip():
        return
    preset_name = res_name.stdout.strip()

    # Step 2: System Prompt
    cmd_prompt = [
        "zenity", "--entry",
        "--title=Add System Prompt",
        "--text=Enter the LLM System Prompt instructions for this preset:",
        "--entry-text="
    ]
    res_prompt = subprocess.run(cmd_prompt, capture_output=True, text=True, env=env)
    if res_prompt.returncode != 0 or not res_prompt.stdout.strip():
        return
    system_prompt = res_prompt.stdout.strip()

    # Save
    prompts = load_prompts()
    prompts[preset_name] = {
        "prompt": system_prompt,
        "label": f"Running {preset_name}"
    }
    save_prompts(prompts)
    send_notification("OmniRoute QuickFix", f"Added new preset: \"{preset_name}\"", icon="emblem-ok")

def delete_preset():
    """Spawns Zenity selection to delete an existing preset prompt."""
    env = os.environ.copy()
    prompts = load_prompts()
    if len(prompts) <= 1:
        send_notification("OmniRoute QuickFix", "Cannot delete last remaining preset.", icon="dialog-warning")
        return

    cmd = [
        "zenity", "--list",
        "--title=Delete Preset Prompt",
        "--text=Select a preset prompt to delete (Use ↑ ↓ arrows & press Enter):",
        "--column=Preset Name",
        "--hide-header"
    ]
    for p_name in prompts.keys():
        cmd.append(p_name)

    res = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if res.returncode == 0 and res.stdout.strip():
        to_delete = res.stdout.strip()
        if to_delete in prompts:
            del prompts[to_delete]
            save_prompts(prompts)
            send_notification("OmniRoute QuickFix", f"Deleted preset: \"{to_delete}\"", icon="user-trash")

def show_zenity_menu():
    """Displays a keyboard-first GTK Zenity dialog. Arrow keys + Enter instantly executes."""
    env = os.environ.copy()
    prompts = load_prompts()

    ADD_OPTION = "➕ Add New Preset Prompt..."
    DEL_OPTION = "🗑️ Delete a Preset Prompt..."

    cmd = [
        "zenity", "--list",
        "--title=OmniRoute QuickFix Menu",
        "--text=Select action (Use ↑ ↓ arrows & press Enter):",
        "--column=Preset", "--column=Description",
        "--hide-header"
    ]

    for name, info in prompts.items():
        cmd.extend([
            name,
            info.get("label", name)
        ])

    cmd.extend([
        ADD_OPTION, "Create a custom prompt preset",
        DEL_OPTION, "Remove an existing prompt preset"
    ])
    cmd.extend(["--width=540", "--height=340"])

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=40, env=env)
        if res.returncode == 0 and res.stdout:
            selection = res.stdout.strip()
            if "|" in selection:
                selection = selection.split("|")[0]
            
            if selection == ADD_OPTION:
                add_new_preset()
                return None
            elif selection == DEL_OPTION:
                delete_preset()
                return None
            return selection
    except Exception:
        pass
    return None

def trigger_workflow(action_key="Grammar Fix"):
    global is_processing
    with lock:
        if is_processing:
            return
        is_processing = True

    def worker():
        global is_processing
        try:
            time.sleep(0.15)
            text = get_clipboard_text()
            if not text or not text.strip():
                send_notification("OmniRoute QuickFix", "No text in clipboard to process.", icon="dialog-warning")
                return

            chosen_preset = action_key
            if action_key == "MENU":
                chosen_preset = show_zenity_menu()
                if not chosen_preset:
                    return

            prompts = load_prompts()
            preset_info = prompts.get(chosen_preset, prompts.get("Grammar Fix", list(prompts.values())[0]))
            system_prompt = preset_info["prompt"]
            label = preset_info.get("label", chosen_preset)

            send_notification("OmniRoute QuickFix", f"✨ {label} ({MODEL_ID})...", icon="sync-synchronizing")

            processed_text = call_omniroute_api(text, system_prompt)
            set_clipboard_text(processed_text)
            play_audio_chime()

            preview = (processed_text[:60].replace('\n', ' ') + '...') if len(processed_text) > 60 else processed_text.replace('\n', ' ')
            send_notification("OmniRoute QuickFix", f"✨ Done! Ready to paste:\n\"{preview}\"", icon="edit-paste")
        except Exception as e:
            send_notification("OmniRoute Error", str(e), icon="dialog-error")
        finally:
            with lock:
                is_processing = False

    threading.Thread(target=worker, daemon=True).start()

def on_press(key):
    global is_ctrl_pressed, is_shift_pressed, ctrl_c_press_times

    if key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
        is_ctrl_pressed = True
    if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
        is_shift_pressed = True

    is_semi_key = False
    if hasattr(key, 'char') and key.char and key.char in (';', ':'):
        is_semi_key = True
    elif hasattr(key, 'vk') and key.vk in (59, 186, 47):
        is_semi_key = True
    elif str(key).lower() in ("';'", "':'"):
        is_semi_key = True

    is_c_key = False
    if hasattr(key, 'char') and key.char and (key.char.lower() == 'c' or key.char == '\x03'):
        is_c_key = True
    elif hasattr(key, 'vk') and key.vk in (67, 99):
        is_c_key = True
    elif str(key).lower() in ("'c'", "'\\x03'", "'c'", "<67>", "<99>"):
        is_c_key = True

    if is_ctrl_pressed:
        if is_semi_key:
            trigger_workflow(action_key="MENU")

        elif is_c_key and not is_shift_pressed:
            now = time.time()
            ctrl_c_press_times = [t for t in ctrl_c_press_times if now - t <= TIME_WINDOW_SEC]
            ctrl_c_press_times.append(now)

            if len(ctrl_c_press_times) >= REQUIRED_PRESSES:
                ctrl_c_press_times.clear()
                trigger_workflow(action_key="Grammar Fix")

def on_release(key):
    global is_ctrl_pressed, is_shift_pressed
    if key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
        is_ctrl_pressed = False
    if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
        is_shift_pressed = False

def main():
    print("OmniRoute QuickFix v3.4 Listener Running...")
    print(f"Endpoint: {OMNIROUTE_URL} | Model: {MODEL_ID}")
    print("- 3x Ctrl+C: Instant Grammar Fix")
    print("- 1x Ctrl+Shift+; (or 1x Ctrl+;): Immediate Keyboard-First Zenity Menu")

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()

if __name__ == "__main__":
    main()
