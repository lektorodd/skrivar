import SwiftUI
import AppKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "App")

/// File-level reference to the onboarding window (needed because SkrivarApp is a struct)
private var onboardingWindow: NSWindow?

@main
struct SkrivarApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow
    private let keyListener = KeyListener()
    private let recorder = AudioRecorder()
    private let overlay = OverlayPanel()
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

        // Wire audio level → overlay waveform
        recorder.onAudioLevel = { [self] level in
            DispatchQueue.main.async {
                overlay.updateAudioLevel(level)
            }
        }

        // Only start listening/recording/keychain if onboarding is already done.
        // On first launch, these are deferred until onboarding completes.
        let onboardingDone = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if onboardingDone {
            keyListener.start()
            recorder.prewarm()
            // Pre-flight keychain access so macOS prompts appear at startup, not during recording
            _ = KeychainHelper.loadGeminiKey()
            _ = KeychainHelper.loadAPIKey()
        }

        // Apply dock icon preference
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        logger.info("Skrivar started (onboarding \(onboardingDone ? "done" : "pending"))")

        // Show onboarding on first launch via AppKit (SwiftUI .task on MenuBarExtra
        // only fires when menu is clicked, so we create the window directly)
        if !onboardingDone {
            // Observe onboarding completion (must use NotificationCenter directly,
            // not SwiftUI .onReceive, because MenuBarExtra content hasn't rendered yet)
            NotificationCenter.default.addObserver(
                forName: .onboardingCompleted,
                object: nil,
                queue: .main
            ) { [keyListener, recorder, appState] _ in
                // Just hide — don't close/dealloc (NSHostingView + @Observable crashes on dealloc)
                onboardingWindow?.orderOut(nil)
                keyListener.start()
                recorder.prewarm()
                _ = KeychainHelper.loadGeminiKey()
                _ = KeychainHelper.loadAPIKey()
                appState.refreshAPIKeyStatus()
                logger.info("Post-onboarding activation complete")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                let hostingView = NSHostingView(rootView: OnboardingView(appState: appState))
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                window.title = "Welcome to Skrivar"
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                onboardingWindow = window
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
        appState.isRecording ? MenuBarIcon.recording() : MenuBarIcon.idle()
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

            // Info section
            Button("Language: \(appState.languageDisplayName)") { }
                .disabled(true)

            Button(appState.apiKeySet ? "API Key: ✓" : "⚠️ API Key: Not Set") { }
                .disabled(true)

            if appState.obsidianConfigured {
                Button("Obsidian: \(appState.obsidianVaultName)/\(appState.obsidianFolder)") { }
                    .disabled(true)
            }

            Divider()

            // Shortcuts reference
            Button("⌃⌥  Quick capture") { }.disabled(true)
            Button("⌃⌥⇧  Translate") { }.disabled(true)
            Button("⌃⌥⌘  Raw Dictation") { }.disabled(true)
            Button("⌃⌥⌘⇧  Flash (synthesize)") { }.disabled(true)

            Divider()

            // Raw session status
            if appState.isRawSession {
                Button("◉ Raw session · \(appState.rawSessionChunkCount) chunks") { }
                    .disabled(true)
                Button("End session") {
                    _ = appState.endRawSession()
                    appState.statusMessage = "Raw session ended"
                }
            }

            // Session stats
            Button("📊 Session: \(appState.sessionTranscriptions) transcriptions") { }
                .disabled(true)

            if appState.sessionGeminiTokens > 0 {
                Button("🔤 Gemini tokens: \(appState.sessionGeminiTokens)") { }
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
            try recorder.start()
            SoundManager.play(.recordStart)
            appState.isRecording = true
            appState.currentMode = mode
            appState.lockedMode = mode  // Lock mode at start
            appState.statusMessage = "\(mode.rawValue) — Recording..."
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
        appState.statusMessage = "Transcribing..."
        logger.info("Recording stopped, \(wavData.count) bytes, mode: \(mode.rawValue)")

        DispatchQueue.main.async {
            overlay.updateStatus("Transcribing…")
        }

        guard !wavData.isEmpty else {
            appState.statusMessage = "No audio"
            DispatchQueue.main.async { overlay.hide() }
            return
        }

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey() else {
                    await MainActor.run {
                        appState.statusMessage = "No API key"
                        overlay.hide()
                    }
                    return
                }
                // Step 1: Transcribe with ElevenLabs (with 1 retry on failure)
                var text = ""
                var lastError: Error?

                for attempt in 1...2 {
                    do {
                        text = try await Transcriber.transcribe(
                            wavData: wavData,
                            apiKey: apiKey,
                            languageCode: appState.languageCode
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

                if let error = lastError {
                    let userMessage = Self.friendlyErrorMessage(error)
                    await MainActor.run {
                        appState.statusMessage = userMessage
                        overlay.hide()
                        SoundManager.play(.error)
                    }
                    return
                }

                guard !text.isEmpty else {
                    await MainActor.run {
                        appState.statusMessage = "No speech detected"
                        overlay.hide()
                    }
                    return
                }

                // Step 2: Route based on mode
                if mode == .obsidianRaw {
                    // Raw dictation: append to Obsidian note, store chunk
                    let success = ObsidianHelper.appendToNote(
                        text: "\n\n\(text)",
                        vault: appState.obsidianVaultName,
                        file: appState.rawSessionNoteFile
                    )
                    await MainActor.run {
                        appState.appendRawChunk(text)
                        history.add(mode: mode, text: text, wasPolished: false)
                        appState.recordTranscription(chars: text.count, method: nil, geminiUsage: nil)
                        appState.statusMessage = success
                            ? "◉ Raw · \(appState.rawSessionChunkCount) chunks"
                            : "❌ Obsidian append error"
                        overlay.hide()
                        SoundManager.play(success ? .transcribeDone : .error)
                    }
                    logger.info("Raw chunk \(appState.rawSessionChunkCount): \(text.count) chars")
                    return
                }

                // Step 2b: Optional Gemini polish (for translate mode)
                var finalText = text
                var geminiUsage: GeminiUsage? = nil
                let shouldPolish = (mode == .translate)

                if shouldPolish {
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

                // Step 3: Deliver text (quick capture or translate)
                let method = TextInserter.insert(finalText)
                await MainActor.run {
                    history.add(mode: mode, text: finalText, wasPolished: shouldPolish)
                    appState.recordTranscription(chars: finalText.count, method: method, geminiUsage: geminiUsage)
                    appState.statusMessage = "✓ \(finalText.count) chars via \(method.rawValue)"
                    overlay.hide()
                    SoundManager.play(.transcribeDone)
                }
                logger.info("Pasted \(finalText.count) chars via \(method.rawValue)")

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
                    appState.statusMessage = Self.friendlyErrorMessage(error)
                    overlay.hide()
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
}
