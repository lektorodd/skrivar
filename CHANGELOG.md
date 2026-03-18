# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.5.1] - 2026-03-18

### Fixed
- **Clipboard race condition** — increased post-paste delay from 150ms to 500ms so Electron apps (VS Code, Slack, Discord) and web apps have time to read the paste before clipboard is restored; previously the old clipboard content could be pasted instead of the transcription
- **Clipboard restore safety** — clipboard save/restore now uses a `defer` block so the original clipboard is always restored, even if an unexpected error occurs during paste
- **Thread safety** — text insertion via clipboard (pasteboard access + CGEvent) now always runs on the main thread; previously the direct-paste path could run on a background thread, causing intermittent paste failures

## [0.5.0] - 2026-03-16

### Added
- **Customizable global hotkey** — choose trigger combo in Settings: ⌃⌥ (default), ⌃⇧, or ⌥⇧
- **Preview before paste** — opt-in floating panel to review/edit transcribed text before pasting (⏎ paste, ⎋ discard, ⌘E edit, auto-paste after 5s)
- **Per-app insertion rules** — override text insertion method (Auto/AX API/Clipboard) per app in Settings
- **Conditional audio compression** — recordings longer than 30s are automatically compressed from WAV to AAC (64kbps) before upload
- **Settings: Delivery section** — preview toggle with description
- **Settings: compression toggle** — enable/disable compression in Settings → Audio

### Changed
- **Settings reorganized** — split into General and Audio tabs for better navigation
- **Menu bar dropdown** — stripped to essentials (status, settings, quit)
- **Update checker** — dev builds no longer show false "Update available" banner

### Fixed
- **Overlay pill light mode** — waveform bars and border now use adaptive color (dark in light mode, white in dark mode)
- **Overlay pill corners** — removed rectangular artifact visible behind the capsule shape
- **Preview panel appearance** — respects system light/dark mode (utility window, not HUD)

## [0.4.3] - 2026-03-15

### Changed
- **Menu bar dropdown** — stripped to essentials
- **Update checker** — dev builds skip update check

## [0.4.2] - 2026-03-15

### Added
- **Quick Retake** — release `⌃⌥` and re-press within 1s to cancel in-flight transcription and start fresh recording; overlay flashes "↺ Retake"
- **Cancel transcription** — press Escape during transcription to abort entirely (no paste, no API waste)
- **Auto-stop on silence (VAD)** — optional setting to automatically stop recording after configurable seconds of silence (1-10s, default 3s, off by default)
- **Settings: Recording section** — new section in General settings with VAD toggle and silence duration stepper

## [0.4.1] - 2026-03-15

### Added
- **Animated menu bar icon** — waveform bars now pulse during recording and transcription (idle → recording bars → processing bars → idle)
- **Error display in overlay** — errors now show in the floating pill overlay with red accent styling, auto-hides after 3 seconds

### Fixed
- **Clipboard preservation** — clipboard fallback paste now saves and restores ALL pasteboard types (images, files, RTF), not just plain text; previously non-text clipboard contents were silently destroyed

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
- **App is damaged error** — added ad-hoc code signing and `ditto` zipping to `build_app.sh` to prevent Gatekeeper from entirely blocking the downloaded ZIP
- **Duplicate app instances** — killed old process before launching new build

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
