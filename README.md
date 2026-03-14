<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white" alt="macOS 14+"/>
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white" alt="Swift 5.9"/>
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License"/>
</p>

<h1 align="center">✦ Skrivar</h1>

<p align="center">
  <strong>A native macOS menu bar app that turns speech into text — instantly.</strong><br/>
  Hold ⌃⌥, speak, release. Your words appear wherever the cursor is.
</p>

---

## What it does

Skrivar lives in your menu bar and listens when you tell it to.  
Hold **⌃⌥** (Control + Option), speak into your mic, and release — transcribed text is pasted directly into the active app. No windows, no copy-paste, no context switching.

**Four capture modes** via modifier combos:

| Shortcut | Mode | What happens |
|----------|------|-------------|
| `⌃⌥` | Quick | Transcribe → paste |
| `⌃⌥⇧` | Translate | Transcribe → Gemini (Nynorsk/polish) → paste |
| `⌃⌥⌘` | Obsidian | Transcribe → new Obsidian note |
| `⌃⌥⌘⇧` | Obsidian+ | Transcribe → Gemini polish → Obsidian note |

## Features

- **Push-to-talk** — hold to record, release to transcribe. No buttons to click.
- **ElevenLabs Scribe v2** — high-quality multilingual speech-to-text.
- **Gemini Flash polishing** — optional AI post-processing for cleaner output, with dedicated Nynorsk translation support.
- **Obsidian integration** — send transcriptions directly as new notes via URI scheme.
- **Live waveform overlay** — Dynamic Island-style floating pill with real-time audio levels.
- **Custom app & menu bar icon** — waveform+cursor design, monochrome template for menu bar.
- **Transcription history** — browse and copy your last 50 transcriptions.
- **Multi-language** — Norwegian (Bokmål & Nynorsk), English, German, French, Spanish, or auto-detect.
- **Sound effects** — audio feedback for record start/stop, success, and errors.
- **Optional dock icon** — toggle in Settings; Skrivar always lives in the menu bar.
- **Launch at Login** — optional auto-start via macOS ServiceManagement.
- **Onboarding wizard** — guided first-launch setup with permission checks.
- **Error retry** — automatic retry with user-friendly error messages.
- **Secure storage** — API keys stored in macOS Keychain, never on disk.

## Requirements

- macOS 14 (Sonoma) or later
- [ElevenLabs](https://elevenlabs.io) API key (required)
- [Google Gemini](https://ai.google.dev) API key (optional — for translate/polish modes)
- Accessibility permission (for keyboard listener)
- Microphone permission

## Getting started

### Build from source

```bash
git clone https://github.com/yourusername/skrivar.git
cd skrivar
swift build -c release
```

The compiled binary will be at `.build/release/Skrivar`.

### Deploy as .app bundle

```bash
# Build release
swift build -c release

# Create .app bundle
mkdir -p /Applications/Skrivar.app/Contents/{MacOS,Resources}
cp .build/release/Skrivar /Applications/Skrivar.app/Contents/MacOS/
cp Resources/AppIcon.icns /Applications/Skrivar.app/Contents/Resources/

# Info.plist is needed — see docs for template
```

### First launch

1. Open Skrivar — it appears in the menu bar with a waveform icon.
2. Grant **Accessibility** and **Microphone** permissions when prompted.
3. Enter your ElevenLabs API key in Settings (and optionally Gemini key).
4. Hold **⌃⌥**, speak, release. Done.

## Architecture

```
Sources/Skrivar/
├── SkrivarApp.swift           # App entry, menu bar, recording lifecycle
├── AppState.swift             # Observable state (settings, stats)
├── KeyListener.swift          # Global hotkey via NSEvent monitor
├── AudioRecorder.swift        # Mic capture → WAV (AVAudioEngine)
├── Transcriber.swift          # ElevenLabs Scribe v2 API client
├── GeminiProcessor.swift      # Gemini Flash post-processing
├── TextInserter.swift         # Paste via Accessibility API / Cmd+V
├── OverlayPanel.swift         # Floating pill overlay with waveform
├── MenuBarIcon.swift          # Custom drawn menu bar icons
├── SoundManager.swift         # System sound effects
├── SettingsView.swift         # SwiftUI settings window
├── OnboardingView.swift       # First-launch wizard
├── TranscriptionHistory.swift # Persistent history store
├── ObsidianHelper.swift       # Obsidian URI scheme integration
├── KeychainHelper.swift       # Secure API key storage
└── LaunchAtLogin.swift        # SMAppService wrapper
```

## Configuration

All settings are accessible from the menu bar → **Settings…**

| Setting | Location | Notes |
|---------|----------|-------|
| ElevenLabs API key | Settings → API Keys | Required |
| Gemini API key | Settings → API Keys | Optional |
| Language | Settings → General | Default: Norwegian |
| Target language | Settings → General | Default: Nynorsk |
| Sound effects | Settings → General | On by default |
| Launch at Login | Settings → System | Off by default |
| Show dock icon | Settings → System | Off by default |
| Obsidian vault/folder | Settings → Obsidian | Required for Obsidian modes |
| Microphone input | Settings → General | Uses system default |

## Name

*Skrivar* is Nynorsk for *writer*.

## License

MIT
