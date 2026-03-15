# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-03-15

### Added
- **Skip button** for API key entry during onboarding — lets returning users skip key re-entry
- **Permissions section** in Settings for managing Accessibility and Microphone permissions post-onboarding
- **Live permission status** in onboarding — polls every 2s with ✓/✗ indicators and Grant buttons

### Changed
- **Onboarding rewritten** — fixed shortcut labels (`⌥-` → `⌃⌥`), added live permission indicators, Grant buttons for Accessibility/Microphone, and macOS update warning for Accessibility re-grants
- **Permission prompts deferred** — keychain, microphone, and keyboard listener activation now delayed until after onboarding completes on first launch
- **Onboarding window** uses AppKit NSWindow directly (no URL scheme) for reliable first-launch display
- **Keychain security** — added `kSecAttrAccessibleWhenUnlocked` to all Keychain operations

### Fixed
- **Post-onboarding crash** — `EXC_BAD_ACCESS` when closing onboarding window; now hidden via `orderOut` instead of `close` to avoid NSHostingView + @Observable deallocation crash
- **Onboarding not showing** — was trying to open via URL scheme from `init()` where `openWindow` isn't available

## [0.3.0] - 2026-03-14

### Added
- **Onboarding wizard** — 4-step first-launch setup (welcome, permissions with System Settings deeplinks, API keys, ready screen with shortcut reference)
- **Launch at Login** toggle via SMAppService in Settings > General > System
- **Configurable trigger key** — choose between minus, right arrow, space, or return via Settings (⌥ + key combos)
- **Error retry** — automatic 1 retry with 1s delay for failed transcriptions
- **User-friendly error messages** — actionable feedback for network, auth, rate limit, and server errors

## [0.2.0] - 2026-03-14

Major UX, performance, and visual improvements.

### Added
- **Live waveform overlay** with 7-bar audio visualization driven by real-time mic levels
- **Recording timer** showing elapsed time (M:SS) in the overlay
- **Transcription history** — last 50 transcriptions stored persistently with copy-to-clipboard
- **History tab** in Settings with mode badges, timestamps, and per-entry copy button
- **Sound effects** for recording lifecycle (Tink on start, Pop on stop, Glass on success, Basso on error)
- **Sounds toggle** in Settings > General > Sound Effects
- **Microphone input selector** in Settings — choose any available audio input device
- **Audio engine pre-warm** at app launch for faster first recording

### Changed
- **Hotkey changed** from Right Option to **Control + Option** — Right Option alone was unusable on Norwegian keyboards (used for `[]`, `{}`, `»«`, `@`, etc.)
- **Overlay animations** — spring entrance/exit with opacity and scale transitions
- **Settings window** widened to accommodate new Microphone and Sound Effects sections
- All shortcut labels updated throughout menu and Settings UI

### Fixed
- Accidental recording triggered when typing special characters on Norwegian keyboard layout
- Audio buffer allocation now pre-reserves capacity for ~10 seconds to reduce reallocation

## [0.1.0] - 2026-03-14

Initial release of Skrivar — a macOS menu bar speech-to-text app.

### Added
- **Menu bar app** with idle/recording icon states and native macOS integration
- **Push-to-talk recording** via right Option key (hold to record, release to transcribe)
- **ElevenLabs Scribe v2** integration for high-quality speech-to-text transcription
- **Multi-language support**: Norwegian (Bokmål & Nynorsk), English, German, French, Spanish, and auto-detect
- **Gemini Flash post-processing** for optional AI-powered transcription refinement (especially Nynorsk correction)
- **Auto-paste** transcribed text into the active app via simulated Cmd+V with clipboard save/restore
- **Overlay panel** showing recording status with animated waveform indicator
- **Dual capture modes**: quick capture vs. translate with distinct hotkey combinations
- **Obsidian integration** for saving transcriptions as new notes via URI scheme (configurable vault/folder)
- **Settings window** with tabbed UI for API key management (ElevenLabs + Gemini), language selection, and Obsidian config
- **Secure API key storage** in macOS Keychain via `KeychainHelper`
- **Native Swift implementation** (macOS 14+) alongside legacy Python (rumps) version
- **Landing page** (`docs/`) for the project

### Security
- API keys stored securely in macOS Keychain, never written to disk in plaintext
