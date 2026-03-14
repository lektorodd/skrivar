"""Pure PyObjC menubar test — no rumps."""
import sys, os
# Add venv site-packages
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(proj, "venv", "lib", "python3.12", "site-packages"))

from AppKit import (
    NSApplication,
    NSStatusBar,
    NSVariableStatusItemLength,
    NSMenu,
    NSMenuItem,
    NSImage,
)

print("[test] Creating NSApplication...")
app = NSApplication.sharedApplication()
app.setActivationPolicy_(1)  # NSApplicationActivationPolicyAccessory

print("[test] Creating status bar item...")
statusbar = NSStatusBar.systemStatusBar()
statusitem = statusbar.statusItemWithLength_(NSVariableStatusItemLength)
button = statusitem.button()
button.setTitle_("🎙 Skrivar")
print(f"[test] Button: {button}, title: {button.title()}")

menu = NSMenu.alloc().init()
quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Quit", "terminate:", "q")
menu.addItem_(quit_item)
statusitem.setMenu_(menu)

print("[test] Running... look for '🎙 Skrivar' in menubar")
app.run()
