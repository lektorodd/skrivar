<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white" alt="macOS 14+"/>
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white" alt="Swift 5.9"/>
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License"/>
</p>

<h1 align="center">✏️ Skrivar</h1>

<p align="center">
  <strong>A native macOS menu bar app that turns speech into text — instantly.</strong><br/>
  Hold a hotkey, speak, release. Your words appear wherever the cursor is.
</p>

---

## What it does

Skrivar lives in your menu bar and listens when you tell it to.  
Hold **⌥ + −** (Option + minus), speak into your mic, and release — transcribed text is pasted directly into the active app. No windows, no copy-paste, no context switching.

**Four capture modes** via modifier combos:

| Shortcut | Mode | What happens |
|----------|------|-------------|
| `⌥ -` | Quick | Transcribe → paste |
| `⌥ ⇧ -` | Translate | Transcribe → Gemini polish → paste |
| `⌥ ⌘ -` | Obsidian | Transcribe → new Obsidian note |
| `⌥ ⌘ ⇧ -` | Obsidian+ | Transcribe → Gemini polish → Obsidian note |

## Features

- **Push-to-talk** — hold to record, release to transcribe. No buttons to click.
- **ElevenLabs Scribe v2** — high-quality multilingual speech-to-text.
- **Gemini Flash polishing** — optional AI post-processing for cleaner output, especially useful for Nynorsk.
- **Obsidian integration** — send transcriptions directly as new notes via URI scheme.
- **Live waveform overlay** — Dynamic Island-style floating pill with real-time audio visualization.
- **Transcription history** — browse and copy your last 50 transcriptions.
- **Multi-language** — Norwegian (Bokmål & Nynorsk), English, German, French, Spanish, or auto-detect.
- **Sound effects** — audio feedback for record start/stop, success, and errors.
- **Configurable trigger key** — choose between minus, right arrow, space, or return.
- **Launch at Login** — optional auto-start via macOS ServiceManagement.
- **Onboarding wizard** — guided first-launch setup with permission checks.
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

### Build as .app bundle

```bash
./build_app.sh
```

This creates `Skrivar.app` in the `build/` directory, ready to drag into `/Applications`.

### First launch

1. Open Skrivar — it appears in the menu bar as `✏️`.
2. The onboarding wizard walks you through granting permissions and entering API keys.
3. Hold **⌥ −**, speak, release. Done.

## Architecture

```
Sources/Skrivar/
├── SkrivarApp.swift          # App entry point, menu bar, recording lifecycle
├── AppState.swift            # Observable state (settings, session stats)
├── KeyListener.swift         # Global hotkey listener via CGEvent tap
├── AudioRecorder.swift       # Mic capture → WAV buffer (AVAudioEngine)
├── Transcriber.swift         # ElevenLabs Scribe v2 API client
├── GeminiProcessor.swift     # Gemini Flash post-processing
├── TextInserter.swift        # Paste text via Accessibility API / Cmd+V
├── OverlayPanel.swift        # Floating pill overlay with waveform
├── SoundManager.swift        # System sound effects
├── SettingsView.swift        # SwiftUI settings window
├── OnboardingView.swift      # First-launch wizard
├── TranscriptionHistory.swift# Persistent history store
├── ObsidianHelper.swift      # Obsidian URI scheme integration
├── KeychainHelper.swift      # Secure API key storage
└── LaunchAtLogin.swift       # SMAppService wrapper
```

## Configuration

All settings are accessible from the menu bar → **Settings…**

| Setting | Location | Notes |
|---------|----------|-------|
| ElevenLabs API key | Settings → API Keys | Required |
| Gemini API key | Settings → API Keys | Optional |
| Language | Settings → General | Default: Norwegian (Bokmål) |
| Trigger key | Settings → General | Default: minus |
| Sound effects | Settings → General | On by default |
| Launch at Login | Settings → General | Off by default |
| Obsidian vault/folder | Settings → Obsidian | Required for Obsidian modes |
| Microphone input | Settings → General | Uses system default |

## Name

*Skrivar* is Nynorsk for *writer*.

## License

MIT
