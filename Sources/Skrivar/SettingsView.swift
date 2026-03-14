import SwiftUI

/// Settings view with tabbed layout: General, API Keys, Stats.
struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }

            APIKeysTab(appState: appState)
                .tabItem { Label("API Keys", systemImage: "key") }

            StatsTab(appState: appState)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Language:", selection: $appState.languageCode) {
                    ForEach(AppState.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("Gemini Polish") {
                Picker("Polish to:", selection: $appState.geminiTargetLanguage) {
                    ForEach(AppState.geminiLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Text("Used in **Translate** (⌥ᴿ⇧) and **Obsidian+** (⌥ᴿ⌘⇧) modes")
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
                    shortcutRow("Right ⌥", "Quick capture → paste")
                    shortcutRow("Right ⌥ + ⇧", "Translate → paste")
                    shortcutRow("Right ⌥ + ⌘", "Capture → Obsidian")
                    shortcutRow("Right ⌥ + ⌘ + ⇧", "Polish → Obsidian")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
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
