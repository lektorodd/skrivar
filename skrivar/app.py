"""Main Skrivar menubar application."""

import threading
import time

import objc
import pyperclip
import rumps
from Foundation import NSObject
from pynput import keyboard
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventSetFlags,
    CGEventPost,
    kCGEventFlagMaskCommand,
    kCGHIDEventTap,
)

from skrivar import config, icons, recorder, transcriber
from skrivar.overlay import Overlay

# Map language display names to ISO 639 codes
LANGUAGES = {
    "Norsk (bokmål)": "nor",
    "Norsk (nynorsk)": "nno",
    "English": "eng",
    "Deutsch": "deu",
    "Français": "fra",
    "Español": "spa",
    "Auto-detect": "",
}


class MainThreadRunner(NSObject):
    """Helper to run a callable on the main thread."""

    def initWithFunc_(self, func):
        self = objc.super(MainThreadRunner, self).init()
        if self is None:
            return None
        self._func = func
        return self

    def run_(self, _):
        self._func()


def perform_on_main_thread(func):
    """Execute a function on the main (AppKit) thread."""
    runner = MainThreadRunner.alloc().initWithFunc_(func)
    runner.performSelectorOnMainThread_withObject_waitUntilDone_(
        "run:", None, False
    )


class SkrivarApp(rumps.App):
    """Mac menubar speech-to-text app."""

    def __init__(self):
        print("[skrivar] Starting...")

        # Create icons
        self._idle_icon = icons.create_idle_icon()
        self._recording_icon = icons.create_recording_icon()
        print(f"[skrivar] Icons: idle={self._idle_icon}, rec={self._recording_icon}")

        super().__init__(
            name="Skrivar",
            icon=self._idle_icon,
            template=None,
            quit_button=None,
        )
        # Ensure menubar item is always visible
        self.title = "Skrivar"

        # Components
        self._recorder = recorder.Recorder()
        self._overlay = Overlay()
        self._key_listener = None
        self._recording_active = False
        print("[skrivar] Components initialized")

        # Build menu
        lang_code = config.get_language_code()
        lang_name = self._code_to_name(lang_code)

        self._settings_item = rumps.MenuItem("Settings…", callback=self._on_settings)
        self._lang_item = rumps.MenuItem(
            f"Language: {lang_name}", callback=self._on_language
        )
        self._status_item = rumps.MenuItem(
            "API Key: ✓" if config.has_api_key() else "API Key: Not Set"
        )
        self._quit_item = rumps.MenuItem("Quit Skrivar", callback=self._on_quit)

        self.menu = [
            self._settings_item,
            None,
            self._lang_item,
            None,
            self._status_item,
            None,
            self._quit_item,
        ]

        # Start keyboard listener
        self._start_key_listener()

        # Prompt for API key on first launch
        if not config.has_api_key():
            def _first_launch_notice():
                time.sleep(1.0)
                perform_on_main_thread(lambda: rumps.notification(
                    "Skrivar",
                    "Setup Required",
                    "Click the menubar icon and open Settings to add your API key.",
                ))
            threading.Thread(target=_first_launch_notice, daemon=True).start()

    # ── Language helpers ──────────────────────────────────────────────────

    def _code_to_name(self, code: str) -> str:
        for name, c in LANGUAGES.items():
            if c == code:
                return name
        return code or "Auto-detect"

    # ── Keyboard listener ─────────────────────────────────────────────────

    def _start_key_listener(self):
        def on_press(key):
            if key == keyboard.Key.alt_r and not self._recording_active:
                self._on_record_start()

        def on_release(key):
            if key == keyboard.Key.alt_r and self._recording_active:
                self._on_record_stop()

        self._key_listener = keyboard.Listener(
            on_press=on_press,
            on_release=on_release,
        )
        self._key_listener.daemon = True
        self._key_listener.start()

    # ── Recording lifecycle ───────────────────────────────────────────────

    def _on_record_start(self):
        if not config.has_api_key():
            perform_on_main_thread(lambda: rumps.notification(
                "Skrivar", "No API Key",
                "Set your ElevenLabs API key in Settings first.",
            ))
            return

        self._recording_active = True
        self._recorder.start()
        perform_on_main_thread(self._show_recording_ui)

    def _on_record_stop(self):
        if not self._recording_active:
            return

        self._recording_active = False
        wav_bytes = self._recorder.stop()
        perform_on_main_thread(self._hide_recording_ui)

        if wav_bytes:
            threading.Thread(
                target=self._transcribe_and_paste,
                args=(wav_bytes,),
                daemon=True,
            ).start()

    def _show_recording_ui(self):
        self.icon = self._recording_icon
        self._overlay.show()

    def _hide_recording_ui(self):
        self.icon = self._idle_icon
        self._overlay.hide()

    # ── Transcription & paste ─────────────────────────────────────────────

    def _transcribe_and_paste(self, wav_bytes: bytes):
        api_key = config.get_api_key()
        lang_code = config.get_language_code()
        text = transcriber.transcribe(wav_bytes, api_key, lang_code)

        if text and not text.startswith("[Transcription error"):
            # Save clipboard → paste transcription → restore clipboard
            try:
                old_clipboard = pyperclip.paste()
            except Exception:
                old_clipboard = ""

            pyperclip.copy(text)
            time.sleep(0.05)
            # Simulate Cmd+V using native Quartz events (avoids pyautogui/rubicon)
            # Key code 9 = 'v' on macOS
            v_down = CGEventCreateKeyboardEvent(None, 9, True)
            v_up = CGEventCreateKeyboardEvent(None, 9, False)
            CGEventSetFlags(v_down, kCGEventFlagMaskCommand)
            CGEventSetFlags(v_up, kCGEventFlagMaskCommand)
            CGEventPost(kCGHIDEventTap, v_down)
            CGEventPost(kCGHIDEventTap, v_up)
            time.sleep(0.15)

            try:
                pyperclip.copy(old_clipboard)
            except Exception:
                pass
        elif text:
            err_text = text
            perform_on_main_thread(
                lambda: rumps.notification("Skrivar", "Error", err_text)
            )

    # ── Menu callbacks ────────────────────────────────────────────────────

    def _on_settings(self, _):
        current_key = config.get_api_key() or ""
        display_key = current_key[:8] + "…" if len(current_key) > 8 else current_key

        response = rumps.Window(
            title="Skrivar — Settings",
            message=(
                "Enter your ElevenLabs API key:\n"
                "(Get one at elevenlabs.io/app/settings/api-keys)"
            ),
            default_text=display_key,
            ok="Save",
            cancel="Cancel",
            dimensions=(320, 24),
        ).run()

        if response.clicked:
            new_key = response.text.strip()
            if new_key and new_key != display_key:
                config.set_api_key(new_key)
                self._status_item.title = "API Key: ✓"
                rumps.notification(
                    "Skrivar", "Saved",
                    "API key stored in macOS Keychain.",
                )

    def _on_language(self, _):
        current_code = config.get_language_code()
        current_name = self._code_to_name(current_code)
        lang_names = list(LANGUAGES.keys())

        options_text = "\n".join(
            f"{'→ ' if name == current_name else '   '}{i + 1}. {name}"
            for i, name in enumerate(lang_names)
        )

        response = rumps.Window(
            title="Skrivar — Language",
            message=f"Enter the number for your language:\n\n{options_text}",
            default_text="",
            ok="Set",
            cancel="Cancel",
            dimensions=(320, 24),
        ).run()

        if response.clicked:
            try:
                choice = int(response.text.strip()) - 1
                if 0 <= choice < len(lang_names):
                    name = lang_names[choice]
                    config.set_language_code(LANGUAGES[name])
                    self._lang_item.title = f"Language: {name}"
            except (ValueError, IndexError):
                pass

    def _on_quit(self, _):
        if self._key_listener:
            self._key_listener.stop()
        if self._recorder.is_recording:
            self._recorder.stop()
        self._overlay.hide()
        rumps.quit_application()


def main():
    """Run the Skrivar menubar app."""
    print("[skrivar] Creating app...")
    app = SkrivarApp()
    print("[skrivar] App created, calling run()...")
    app.run()
    print("[skrivar] App exited.")


if __name__ == "__main__":
    main()
