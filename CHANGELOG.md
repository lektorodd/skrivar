# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
