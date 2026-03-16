import SwiftUI
import AppKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "App")

@main
struct SkrivarApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow
    private let keyListener = KeyListener()
    private let recorder = AudioRecorder()
    private let overlay = OverlayPanel()
    private let previewPanel = PreviewPanel()
    private let history = TranscriptionHistory()
    @State private var iconPhase: Double = 0.0
    @State private var iconTimer: Timer?

    init() {
        keyListener.onRecordStart = { [self] mode in
            guard appState.apiKeySet else {
                showNotification(
                    title: "Skrivar",
                    message: "Set your API key in Settings first."
                )
                return
            }

            // Quick Retake: if transcription is in flight, cancel it and restart
            if appState.isTranscribing {
                cancelTranscription(hideOverlay: false)
                overlay.updateStatus("↺ Retake")
                logger.info("Retake — cancelled in-flight transcription")
                // Fall through to start a new recording
            }

            // Flash is a non-recording action — trigger synthesis immediately
            if mode == .flash {
                performFlash()
                return
            }

            // When a raw session is active, redirect quick capture to raw append
            let effectiveMode = (mode == .quick && appState.isRawSession) ? .obsidianRaw : mode

            // Start recording after a short delay to filter accidental taps
            appState.pendingRecordTask?.cancel()
            let task = DispatchWorkItem { [self] in
                startRecording(mode: appState.currentMode)
            }
            appState.pendingRecordTask = task
            appState.currentMode = effectiveMode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }

        keyListener.onRecordStop = { [self] in
            // Cancel if released before the hold delay
            if let pending = appState.pendingRecordTask, !pending.isCancelled {
                pending.cancel()
                appState.pendingRecordTask = nil
                // Was never actually recording
                if !appState.isRecording { return }
            }
            stopRecording()
        }

        keyListener.onModeChange = { [self] mode in
            appState.currentMode = mode
            // Only upgrade the locked mode (never downgrade)
            // This prevents losing translate mode when Shift is released before ⌃⌥
            if mode.priority > appState.lockedMode.priority {
                appState.lockedMode = mode
            }
            if appState.isRecording {
                overlay.show(mode: mode)
            }
        }

        // Cancel transcription via Escape key
        keyListener.onCancelPressed = { [self] in
            guard appState.isTranscribing else { return }
            cancelTranscription()
            appState.statusMessage = "Cancelled"
            logger.info("Transcription cancelled via Escape")
            SoundManager.play(.recordStop)
        }

        // Wire audio level → overlay waveform
        recorder.onAudioLevel = { [self] level in
            DispatchQueue.main.async {
                overlay.updateAudioLevel(level)
            }
        }

        // Wire VAD: auto-stop recording on silence
        recorder.onSilenceDetected = { [self] in
            DispatchQueue.main.async {
                guard appState.isRecording else { return }
                logger.info("VAD: silence detected, auto-stopping")
                overlay.updateStatus("Auto-stopped")
                stopRecording()
            }
        }

        keyListener.triggerFlags = appState.triggerModifiers
        keyListener.start()
        recorder.prewarm()

        // Apply dock icon preference
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        logger.info("Skrivar started")

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let url = URL(string: "skrivar://onboarding") {
                    NSWorkspace.shared.open(url)
                }
                // Fallback: open via Environment
                NSApp.windows.first(where: { $0.title.contains("Welcome") })?.makeKeyAndOrderFront(nil)
            }
        }

        // Check for updates on launch
        UpdateChecker.check(appState: appState)
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Image(nsImage: menuBarNSImage)
        }
        .onChange(of: appState.isRecording) { _, _ in }  // Force menu bar icon redraw
        .onChange(of: appState.isTranscribing) { _, _ in }  // Force icon redraw
        .onChange(of: appState.processingIconPhase) { _, _ in }  // Animate dots

        Window("Skrivar Settings", id: "settings") {
            SettingsView(appState: appState, history: history)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to Skrivar", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // MARK: - URL Scheme

    private func handleURL(_ url: URL) {
        guard url.scheme == "skrivar" else { return }
        let action = url.host ?? ""
        logger.info("URL scheme action: \(action)")

        switch action {
        case "raw-session":
            guard appState.obsidianConfigured else {
                showNotification(title: "Skrivar", message: "Set your Obsidian vault in Settings first.")
                return
            }
            if !appState.isRawSession {
                if let noteFile = ObsidianHelper.createRawNote(
                    vault: appState.obsidianVaultName,
                    folder: appState.obsidianFolder
                ) {
                    appState.startRawSession(noteFile: noteFile)
                    appState.statusMessage = "◉ Raw session started"
                    SoundManager.play(.recordStart)
                    logger.info("Raw session started via URL: \(noteFile)")
                }
            }
        case "flash":
            performFlash()
        case "end-session":
            if appState.isRawSession {
                _ = appState.endRawSession()
                appState.statusMessage = "Raw session ended"
                logger.info("Raw session ended via URL (no flash)")
            }
        case "settings":
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        case "onboarding":
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        default:
            logger.warning("Unknown URL action: \(action)")
        }
    }

    private var menuBarNSImage: NSImage {
        if appState.isRecording {
            return MenuBarIcon.recording(phase: appState.processingIconPhase)
        } else if appState.isTranscribing {
            return MenuBarIcon.processing(phase: appState.processingIconPhase)
        } else {
            return MenuBarIcon.idle()
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        Group {
            if appState.isRecording {
                Button("🔴 \(appState.currentMode.rawValue) — Recording...") { }
                    .disabled(true)
            } else {
                Button(appState.statusMessage) { }
                    .disabled(true)
            }

            Divider()

            // Active raw session
            if appState.isRawSession {
                Button("◉ Raw session · \(appState.rawSessionChunkCount) chunks") { }
                    .disabled(true)
                Button("End session") {
                    _ = appState.endRawSession()
                    appState.statusMessage = "Raw session ended"
                }
                Divider()
            }

            // Session stats (only show if there's activity)
            if appState.sessionTranscriptions > 0 {
                Button("📊 \(appState.sessionTranscriptions) transcriptions") { }
                    .disabled(true)
            }

            if appState.sessionGeminiTokens > 0 {
                Button("🔤 \(appState.sessionGeminiTokens) Gemini tokens") { }
                    .disabled(true)
            }

            Divider()

            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            if appState.updateAvailable {
                Button("⬆️ Update available: v\(appState.latestVersion)") {
                    if let url = URL(string: appState.updateURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Button("Quit Skrivar") {
                keyListener.stop()
                if recorder.isRecording {
                    _ = recorder.stop()
                }
                overlay.hide()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Recording

    private func startRecording(mode: CaptureMode) {
        guard !appState.isRecording else { return }

        // Validate mode requirements
        if mode == .obsidianRaw && !appState.obsidianConfigured {
            showNotification(title: "Skrivar", message: "Set your Obsidian vault name in Settings first.")
            return
        }
        if mode == .translate {
            guard let key = KeychainHelper.loadGeminiKey(), !key.isEmpty else {
                showNotification(title: "Skrivar", message: "Set your Gemini API key in Settings for translate mode.")
                return
            }
        }

        // Raw dictation: create Obsidian note on first chunk
        if mode == .obsidianRaw && !appState.isRawSession {
            guard let noteFile = ObsidianHelper.createRawNote(
                vault: appState.obsidianVaultName,
                folder: appState.obsidianFolder
            ) else {
                showNotification(title: "Skrivar", message: "Failed to create Obsidian note.")
                return
            }
            appState.startRawSession(noteFile: noteFile)
            logger.info("Raw session started: \(noteFile)")
        }

        do {
            // Configure VAD
            recorder.silenceThresholdSeconds = appState.vadEnabled ? appState.vadSilenceSeconds : 0
            try recorder.start()
            SoundManager.play(.recordStart)
            appState.isRecording = true
            appState.currentMode = mode
            appState.lockedMode = mode  // Lock mode at start
            appState.statusMessage = "\(mode.rawValue) — Recording..."
            startProcessingAnimation()  // Animate icon from recording start
            DispatchQueue.main.async {
                self.overlay.show(mode: mode)
            }
            logger.info("Recording started — mode: \(mode.rawValue)")
        } catch {
            SoundManager.play(.error)
            logger.error("Failed to start recording: \(error.localizedDescription)")
            appState.statusMessage = "Mic error"
        }
    }

    private func stopRecording() {
        guard appState.isRecording else { return }

        let mode = appState.lockedMode  // Use locked mode, not current
        let wavData = recorder.stop()
        SoundManager.play(.recordStop)
        appState.isRecording = false
        appState.isTranscribing = true
        appState.statusMessage = "Transcribing..."
        logger.info("Recording stopped, \(wavData.count) bytes, mode: \(mode.rawValue)")

        // Start processing icon animation
        startProcessingAnimation()

        DispatchQueue.main.async {
            overlay.updateStatus("Transcribing…")
        }

        guard !wavData.isEmpty else {
            appState.statusMessage = "No audio"
            DispatchQueue.main.async {
                self.stopProcessingAnimation()
                self.appState.isTranscribing = false
                overlay.hide()
            }
            return
        }

        appState.cancellableTranscriptionTask = Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey() else {
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        appState.statusMessage = "No API key"
                        overlay.showError("No API key")
                    }
                    return
                }
                // Step 1: Compress audio if needed (>30s recordings → AAC)
                let compressed = appState.compressionEnabled
                    ? AudioCompressor.compressIfNeeded(wavData: wavData)
                    : AudioCompressor.CompressedAudio(data: wavData, filename: "recording.wav", mimeType: "audio/wav")

                // Step 1b: Transcribe with ElevenLabs (with 1 retry on failure)
                var text = ""
                var lastError: Error?

                for attempt in 1...2 {
                    guard !Task.isCancelled else { return }
                    do {
                        text = try await Transcriber.transcribe(
                            audioData: compressed.data,
                            apiKey: apiKey,
                            languageCode: appState.languageCode,
                            filename: compressed.filename,
                            mimeType: compressed.mimeType
                        )
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        if attempt == 1 {
                            logger.warning("Transcription attempt 1 failed, retrying: \(error.localizedDescription)")
                            await MainActor.run {
                                overlay.updateStatus("Retrying…")
                            }
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                if let error = lastError {
                    let userMessage = Self.friendlyErrorMessage(error)
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        appState.statusMessage = userMessage
                        overlay.showError(userMessage)
                        SoundManager.play(.error)
                    }
                    return
                }

                guard !text.isEmpty else {
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        appState.statusMessage = "No speech detected"
                        overlay.hide()
                    }
                    return
                }

                guard !Task.isCancelled else { return }

                // Step 2: Route based on mode
                if mode == .obsidianRaw {
                    // Raw dictation: append to Obsidian note, store chunk
                    let success = ObsidianHelper.appendToNote(
                        text: "\n\n\(text)",
                        vault: appState.obsidianVaultName,
                        file: appState.rawSessionNoteFile
                    )
                    let capturedText = text
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        appState.appendRawChunk(capturedText)
                        history.add(mode: mode, text: capturedText, wasPolished: false)
                        appState.recordTranscription(chars: capturedText.count, method: nil, geminiUsage: nil)
                        if success {
                            appState.statusMessage = "◉ Raw · \(appState.rawSessionChunkCount) chunks"
                            overlay.hide()
                            SoundManager.play(.transcribeDone)
                        } else {
                            appState.statusMessage = "❌ Obsidian append error"
                            overlay.showError("Obsidian append failed")
                            SoundManager.play(.error)
                        }
                    }
                    logger.info("Raw chunk \(appState.rawSessionChunkCount): \(capturedText.count) chars")
                    return
                }

                // Step 2b: Optional Gemini polish (for translate mode)
                var finalText = text
                var geminiUsage: GeminiUsage? = nil
                let shouldPolish = (mode == .translate)

                if shouldPolish {
                    guard !Task.isCancelled else { return }
                    if let geminiKey = KeychainHelper.loadGeminiKey(), !geminiKey.isEmpty {
                        await MainActor.run {
                            appState.statusMessage = "Polishing..."
                            overlay.updateStatus("Polishing…")
                        }
                        do {
                            let result = try await GeminiProcessor.process(
                                text: text,
                                apiKey: geminiKey,
                                targetLanguage: appState.geminiTargetLanguage
                            )
                            finalText = result.text
                            geminiUsage = result.usage
                        } catch {
                            logger.error("Gemini error (using raw text): \(error.localizedDescription)")
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                // Brief retake window — gives user time to re-press ⌃⌥ to cancel
                // before text is pasted, even if the API responded instantly
                await MainActor.run {
                    overlay.updateStatus("Pasting…")
                }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                // Step 3: Deliver text (quick capture or translate)
                // Track frontmost app for per-app rules Settings UI
                if let app = NSWorkspace.shared.frontmostApplication,
                   let bundleId = app.bundleIdentifier {
                    await MainActor.run {
                        appState.trackApp(bundleId: bundleId, name: app.localizedName ?? bundleId)
                    }
                }

                let usePreview = await MainActor.run { appState.previewEnabled }
                let capturedFinalText = finalText
                let capturedGeminiUsage = geminiUsage

                if usePreview {
                    // Show preview panel instead of auto-pasting
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        overlay.hide()
                        SoundManager.play(.transcribeDone)

                        previewPanel.onPaste = { [self] text in
                            let rules = appState.insertionRules
                            let method = TextInserter.insert(text, rules: rules)
                            history.add(mode: mode, text: text, wasPolished: shouldPolish)
                            appState.recordTranscription(chars: text.count, method: method, geminiUsage: capturedGeminiUsage)
                            appState.statusMessage = "✓ \(text.count) chars via \(method.rawValue)"
                        }
                        previewPanel.onDiscard = { [self] in
                            appState.statusMessage = "Discarded"
                        }
                        previewPanel.show(text: capturedFinalText)
                    }
                } else {
                    // Direct paste (original behavior)
                    let rules = await MainActor.run { appState.insertionRules }
                    let method = TextInserter.insert(capturedFinalText, rules: rules)
                    await MainActor.run {
                        stopProcessingAnimation()
                        appState.isTranscribing = false
                        history.add(mode: mode, text: capturedFinalText, wasPolished: shouldPolish)
                        appState.recordTranscription(chars: capturedFinalText.count, method: method, geminiUsage: capturedGeminiUsage)
                        appState.statusMessage = "✓ \(capturedFinalText.count) chars via \(method.rawValue)"
                        overlay.hide()
                        SoundManager.play(.transcribeDone)
                    }
                }
                logger.info("Delivered \(capturedFinalText.count) chars")

                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if appState.isRawSession {
                        appState.statusMessage = "◉ Raw session · \(appState.rawSessionChunkCount) chunks"
                    } else {
                        appState.statusMessage = "Ready"
                    }
                }

            } catch {
                logger.error("Transcription error: \(error.localizedDescription)")
                await MainActor.run {
                    stopProcessingAnimation()
                    appState.isTranscribing = false
                    let msg = Self.friendlyErrorMessage(error)
                    appState.statusMessage = msg
                    overlay.showError(msg)
                    SoundManager.play(.error)
                }
            }
        }
    }

    /// Convert errors into user-friendly actionable messages.
    private static func friendlyErrorMessage(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()

        if desc.contains("api key") || desc.contains("401") || desc.contains("403") {
            return "❌ Invalid API key — check Settings"
        }
        if desc.contains("network") || desc.contains("connection") || desc.contains("timed out")
            || desc.contains("offline") || desc.contains("not connected") {
            return "❌ No internet — check your connection"
        }
        if desc.contains("429") || desc.contains("rate limit") {
            return "❌ Rate limited — wait a moment"
        }
        if desc.contains("500") || desc.contains("502") || desc.contains("503") {
            return "❌ Server error — try again shortly"
        }
        return "❌ \(error.localizedDescription)"
    }

    // MARK: - Flash (Raw Dictation Synthesis)

    private func performFlash() {
        guard appState.isRawSession else {
            showNotification(title: "Skrivar", message: "No raw session active — start one with ⌃⌥⌘ first.")
            return
        }
        guard let geminiKey = KeychainHelper.loadGeminiKey(), !geminiKey.isEmpty else {
            showNotification(title: "Skrivar", message: "Set your Gemini API key in Settings for Flash.")
            return
        }

        let savedNoteFile = appState.rawSessionNoteFile
        let chunks = appState.endRawSession()

        guard !chunks.isEmpty else {
            appState.statusMessage = "No chunks to synthesize"
            return
        }

        appState.statusMessage = "⚡ Synthesizing..."
        overlay.show(mode: .flash)
        overlay.updateStatus("Synthesizing…")
        SoundManager.play(.recordStop)

        Task {
            do {
                let result = try await GeminiProcessor.synthesize(
                    chunks: chunks,
                    apiKey: geminiKey,
                    targetLanguage: appState.geminiTargetLanguage
                )

                let synthesizedBlock = "\n\n---\n\n## Synthesized\n\n\(result.text)"
                let success = ObsidianHelper.appendToNote(
                    text: synthesizedBlock,
                    vault: appState.obsidianVaultName,
                    file: savedNoteFile
                )

                await MainActor.run {
                    appState.recordTranscription(chars: result.text.count, method: nil, geminiUsage: result.usage)
                    appState.statusMessage = success
                        ? "⚡ \(result.text.count) chars synthesized → Obsidian"
                        : "❌ Failed to append synthesis"
                    overlay.hide()
                    SoundManager.play(success ? .transcribeDone : .error)
                }
                logger.info("Flash: \(chunks.count) chunks → \(result.text.count) chars, \(result.usage.totalTokens) tokens")

                try? await Task.sleep(for: .seconds(5))
                await MainActor.run { appState.statusMessage = "Ready" }

            } catch {
                logger.error("Flash synthesis error: \(error.localizedDescription)")
                await MainActor.run {
                    appState.statusMessage = Self.friendlyErrorMessage(error)
                    overlay.hide()
                    SoundManager.play(.error)
                }
            }
        }
    }

    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Processing Icon Animation

    private func startProcessingAnimation() {
        stopProcessingAnimation()
        appState.processingIconPhase = 0
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [self] _ in
            appState.processingIconPhase = (appState.processingIconPhase + 1) % 3
        }
    }

    private func stopProcessingAnimation() {
        iconTimer?.invalidate()
        iconTimer = nil
        appState.processingIconPhase = 0
    }

    // MARK: - Cancel / Retake

    /// Cancel in-flight transcription, reset state, hide overlay.
    private func cancelTranscription(hideOverlay: Bool = true) {
        appState.cancellableTranscriptionTask?.cancel()
        appState.cancellableTranscriptionTask = nil
        stopProcessingAnimation()
        appState.isTranscribing = false
        if hideOverlay {
            overlay.hide()
        }
    }
}
