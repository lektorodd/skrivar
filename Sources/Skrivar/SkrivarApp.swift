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

            // Start recording after a short delay to filter accidental taps
            appState.pendingRecordTask?.cancel()
            let task = DispatchWorkItem { [self] in
                startRecording(mode: appState.currentMode)
            }
            appState.pendingRecordTask = task
            appState.currentMode = mode
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
    }

    var body: some Scene {
        MenuBarExtra("Skrivar", systemImage: menuBarIcon) {
            menuContent
        }

        Window("Skrivar Settings", id: "settings") {
            SettingsView(appState: appState, history: history)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to Skrivar", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var menuBarIcon: String {
        appState.isRecording ? "waveform" : "character.cursor.ibeam"
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
            Button("⌃⌥⌘  → Obsidian") { }.disabled(true)
            Button("⌃⌥⌘⇧  → Obsidian+") { }.disabled(true)

            Divider()

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
        if (mode == .obsidian || mode == .obsidianPolished) && !appState.obsidianConfigured {
            showNotification(title: "Skrivar", message: "Set your Obsidian vault name in Settings first.")
            return
        }
        if (mode == .translate || mode == .obsidianPolished) {
            guard let key = KeychainHelper.loadGeminiKey(), !key.isEmpty else {
                showNotification(title: "Skrivar", message: "Set your Gemini API key in Settings for polish mode.")
                return
            }
        }

        do {
            try recorder.start()
            SoundManager.play(.recordStart)
            appState.isRecording = true
            appState.currentMode = mode
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

        let mode = appState.currentMode
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

                // Step 2: Optional Gemini polish (for translate & obsidianPolished modes)
                var finalText = text
                var geminiUsage: GeminiUsage? = nil
                let shouldPolish = (mode == .translate || mode == .obsidianPolished)

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

                // Step 3: Deliver the text based on mode
                let isObsidian = (mode == .obsidian || mode == .obsidianPolished)

                if isObsidian {
                    let success = ObsidianHelper.createNote(
                        text: finalText,
                        vault: appState.obsidianVaultName,
                        folder: appState.obsidianFolder
                    )
                    await MainActor.run {
                        history.add(mode: mode, text: finalText, wasPolished: shouldPolish)
                        appState.recordTranscription(chars: finalText.count, method: nil, geminiUsage: geminiUsage)
                        appState.statusMessage = success
                            ? "✓ \(finalText.count) chars → Obsidian"
                            : "❌ Obsidian error"
                        overlay.hide()
                        SoundManager.play(success ? .transcribeDone : .error)
                    }
                    logger.info("Sent \(finalText.count) chars to Obsidian")
                } else {
                    let method = TextInserter.insert(finalText)
                    await MainActor.run {
                        history.add(mode: mode, text: finalText, wasPolished: shouldPolish)
                        appState.recordTranscription(chars: finalText.count, method: method, geminiUsage: geminiUsage)
                        appState.statusMessage = "✓ \(finalText.count) chars via \(method.rawValue)"
                        overlay.hide()
                        SoundManager.play(.transcribeDone)
                    }
                    logger.info("Pasted \(finalText.count) chars via \(method.rawValue)")
                }

                try? await Task.sleep(for: .seconds(3))
                await MainActor.run { appState.statusMessage = "Ready" }

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
