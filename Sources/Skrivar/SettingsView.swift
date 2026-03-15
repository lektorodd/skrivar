import SwiftUI
import AVFoundation

/// Settings view with tabbed layout: General, API Keys, History, Stats.
struct SettingsView: View {
    @Bindable var appState: AppState
    let history: TranscriptionHistory

    var body: some View {
        TabView {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }

            APIKeysTab(appState: appState)
                .tabItem { Label("API Keys", systemImage: "key") }

            HistoryTab(history: history)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            StatsTab(appState: appState)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
        .frame(width: 520, height: 540)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Bindable var appState: AppState
    @State private var soundsEnabled = SoundManager.isEnabled
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var permissionTimer: Timer?
    @State private var triggerKeyCode: Int = {
        let saved = UserDefaults.standard.integer(forKey: "triggerKeyCode")
        return saved > 0 ? saved : 27
    }()

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Language:", selection: $appState.languageCode) {
                    ForEach(AppState.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("Microphone") {
                Picker("Input device:", selection: $appState.audioInputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(AudioRecorder.availableInputDevices()) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                if !appState.audioInputDeviceUID.isEmpty {
                    let deviceName = AudioRecorder.availableInputDevices()
                        .first(where: { $0.uid == appState.audioInputDeviceUID })?.name ?? "Unknown"
                    Text("Using: **\(deviceName)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gemini Polish") {
                Picker("Polish to:", selection: $appState.geminiTargetLanguage) {
                    ForEach(AppState.geminiLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Text("Used in **Translate** (⌃⌥⇧) and **Flash** (⌃⌥⌘⇧) modes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Obsidian") {
                TextField("Vault name", text: $appState.obsidianVaultName)
                    .textFieldStyle(.roundedBorder)

                TextField("Folder (e.g. Inbox)", text: $appState.obsidianFolder)
                    .textFieldStyle(.roundedBorder)

                if appState.obsidianConfigured {
                    Text("✓ Notes will go to **\(appState.obsidianVaultName)/\(appState.obsidianFolder)/**")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Set your vault name to enable Obsidian capture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("⌃⌥", "Quick capture → paste")
                    shortcutRow("⌃⌥⇧", "Translate → paste")
                    shortcutRow("⌃⌥⌘", "Raw Dictation → Obsidian")
                    shortcutRow("⌃⌥⌘⇧", "Flash (synthesize session)")
                }
                .font(.callout)

                Text("Hold **Control + Option** to record, release to transcribe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound Effects") {
                Toggle("Play sounds", isOn: $soundsEnabled)
                    .onChange(of: soundsEnabled) { _, newValue in
                        SoundManager.isEnabled = newValue
                    }

                Text("Audio feedback for recording start, stop, and transcription results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Label("Accessibility", systemImage: "keyboard")
                    Spacer()
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack {
                    Label("Microphone", systemImage: "mic")
                    Spacer()
                    if microphoneGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant") {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async { microphoneGranted = granted }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("After updating Skrivar, you may need to re-grant Accessibility in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                ))

                Toggle("Show dock icon", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "showDockIcon") },
                    set: { show in
                        UserDefaults.standard.set(show, forKey: "showDockIcon")
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                        // Re-show windows after policy change (accessory hides them)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.activate(ignoringOtherApps: true)
                            for window in NSApp.windows where window.title.contains("Settings") {
                                window.makeKeyAndOrderFront(nil)
                            }
                        }
                    }
                ))

                Text("Dock icon is optional — Skrivar always lives in the menu bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Auto-stop on silence", isOn: Binding(
                    get: { appState.vadEnabled },
                    set: { appState.vadEnabled = $0 }
                ))

                if appState.vadEnabled {
                    Stepper(
                        "Silence duration: \(Int(appState.vadSilenceSeconds))s",
                        value: Binding(
                            get: { appState.vadSilenceSeconds },
                            set: { appState.vadSilenceSeconds = $0 }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    Text("Automatically stop recording after \(Int(appState.vadSilenceSeconds)) seconds of silence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                accessibilityGranted = AXIsProcessTrusted()
                microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 160, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - API Keys Tab

struct APIKeysTab: View {
    @Bindable var appState: AppState
    @State private var elevenLabsKey: String = ""
    @State private var geminiKey: String = ""
    @State private var showElevenLabsSaved = false
    @State private var showGeminiSaved = false
    @State private var isElevenLabsVisible = false
    @State private var isGeminiVisible = false

    var body: some View {
        Form {
            Section("ElevenLabs") {
                HStack {
                    if isElevenLabsVisible {
                        TextField("sk_...", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk_...", text: $elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { isElevenLabsVisible.toggle() }) {
                        Image(systemName: isElevenLabsVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save") {
                        let trimmed = elevenLabsKey.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            _ = KeychainHelper.saveAPIKey(trimmed)
                            showElevenLabsSaved = true
                            appState.refreshAPIKeyStatus()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showElevenLabsSaved = false
                            }
                        }
                    }
                    .disabled(elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if showElevenLabsSaved {
                        Text("✓ Saved to Keychain")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .transition(.opacity)
                    }

                    Spacer()

                    if appState.apiKeySet {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Text("Get a key at [elevenlabs.io](https://elevenlabs.io/app/settings/api-keys)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini") {
                HStack {
                    if isGeminiVisible {
                        TextField("AI...", text: $geminiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("AI...", text: $geminiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { isGeminiVisible.toggle() }) {
                        Image(systemName: isGeminiVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save") {
                        let trimmed = geminiKey.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            _ = KeychainHelper.saveGeminiKey(trimmed)
                            showGeminiSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showGeminiSaved = false
                            }
                        }
                    }
                    .disabled(geminiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if showGeminiSaved {
                        Text("✓ Saved to Keychain")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .transition(.opacity)
                    }

                    Spacer()

                    if appState.hasGeminiKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Text("Get a key at [aistudio.google.com](https://aistudio.google.com/apikey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let key = KeychainHelper.loadAPIKey() { elevenLabsKey = key }
            if let key = KeychainHelper.loadGeminiKey() { geminiKey = key }
        }
    }
}

// MARK: - Stats Tab

struct StatsTab: View {
    @Bindable var appState: AppState
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("This Session") {
                statRow("Transcriptions", "\(appState.sessionTranscriptions)")

                if appState.sessionGeminiTokens > 0 {
                    statRow("Gemini tokens", "\(appState.sessionGeminiTokens)")
                }

                if let lastUsage = appState.lastGeminiUsage {
                    statRow("Last Gemini", "\(lastUsage.promptTokens) → \(lastUsage.candidateTokens) tokens")
                }

                if let method = appState.lastInsertionMethod {
                    statRow("Last insert", method.rawValue)
                }
            }

            Section("All Time") {
                statRow("Transcriptions", "\(appState.totalTranscriptions)")
                statRow("Characters", formatNumber(appState.totalCharacters))
                statRow("Gemini tokens", formatNumber(appState.totalGeminiTokens))
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset All-Time Stats") {
                        showResetConfirm = true
                    }
                    .foregroundStyle(.red)
                    .alert("Reset all-time stats?", isPresented: $showResetConfirm) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            appState.resetAllTimeStats()
                        }
                    } message: {
                        Text("This cannot be undone.")
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    let history: TranscriptionHistory
    @State private var showClearConfirm = false
    @State private var copiedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                    Text("Hold **⌃⌥** to start recording")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(history.entries) { entry in
                        historyRow(entry)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                // Footer with count and clear button
                HStack {
                    Text("\(history.entries.count) transcriptions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear All") {
                        showClearConfirm = true
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .alert("Clear transcription history?", isPresented: $showClearConfirm) {
                        Button("Cancel", role: .cancel) { }
                        Button("Clear", role: .destructive) {
                            history.clear()
                        }
                    } message: {
                        Text("This cannot be undone.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func historyRow(_ entry: TranscriptionEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Mode badge
                Text(entry.mode)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(modeBadgeColor(entry.mode).opacity(0.2))
                    .foregroundStyle(modeBadgeColor(entry.mode))
                    .clipShape(Capsule())

                if entry.wasPolished {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(formatTimestamp(entry.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                    copiedId = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedId == entry.id { copiedId = nil }
                    }
                }) {
                    Image(systemName: copiedId == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copiedId == entry.id ? .green : .secondary)
                }
                .buttonStyle(.borderless)
            }

            Text(entry.text)
                .font(.system(size: 11))
                .lineLimit(3)
                .foregroundStyle(.primary)

            Text("\(entry.charCount) chars")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 2)
    }

    private func modeBadgeColor(_ mode: String) -> Color {
        switch mode {
        case "Quick":     return .white
        case "Translate": return Color(red: 0, green: 0.82, blue: 0.70)
        case "Raw":       return Color(red: 0.95, green: 0.75, blue: 0.20)
        case "Flash":     return Color(red: 1.0, green: 0.85, blue: 0.30)
        default:          return .gray
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "d MMM HH:mm"
            return formatter.string(from: date)
        }
    }
}
