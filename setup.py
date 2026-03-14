"""
py2app setup script for Skrivar.
Build with: python setup.py py2app
"""

from setuptools import setup

APP = ["skrivar/__main__.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "plist": {
        "CFBundleName": "Skrivar",
        "CFBundleDisplayName": "Skrivar",
        "CFBundleIdentifier": "com.skrivar.app",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "LSUIElement": True,  # Agent app — menubar only, no dock icon
        "NSMicrophoneUsageDescription": "Skrivar needs microphone access to record speech for transcription.",
        "NSAppleEventsUsageDescription": "Skrivar needs accessibility to paste transcribed text.",
    },
    "packages": ["skrivar"],
    "includes": [
        "rumps",
        "pynput",
        "sounddevice",
        "numpy",
        "scipy",
        "scipy.io",
        "scipy.io.wavfile",
        "elevenlabs",
        "pyperclip",
        "pyautogui",
        "keyring",
        "keyring.backends",
        "keyring.backends.macOS",
        "PIL",
        "objc",
        "AppKit",
        "Foundation",
        "Quartz",
    ],
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
