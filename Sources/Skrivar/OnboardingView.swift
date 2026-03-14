import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "Onboarding")

/// First-launch onboarding wizard.
struct OnboardingView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var geminiKey = ""
    @State private var keySaved = false
    @State private var geminiKeySaved = false

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: Double(currentStep), total: Double(totalSteps - 1))
                .tint(.accentColor)
                .padding(.horizontal, 32)
                .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: apiKeyStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 2 && !keySaved)
                } else {
                    Button("Start Using Skrivar") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to Skrivar")
                .font(.title.weight(.semibold))

            Text("Speech-to-text for your Mac.\nHold **⌥-** to record, release to transcribe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 8) {
                featureRow("waveform", "Record with a keyboard shortcut")
                featureRow("text.bubble", "Instant transcription via ElevenLabs")
                featureRow("sparkles", "Optional AI polish with Gemini")
                featureRow("book.closed", "Save notes directly to Obsidian")
            }
            .padding(.top, 8)
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Permissions")
                .font(.title2.weight(.semibold))

            Text("Skrivar needs two permissions:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    icon: "keyboard",
                    title: "Accessibility",
                    description: "To detect keyboard shortcuts and insert text",
                    action: {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                )

                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "To record audio for transcription",
                    action: {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        )
                    }
                )
            }
            .padding(.horizontal, 32)

            Text("You may need to restart Skrivar after granting permissions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("API Key")
                .font(.title2.weight(.semibold))

            Text("Enter your ElevenLabs API key for transcription.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SecureField("ElevenLabs API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                if keySaved {
                    Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Save Key") {
                        if KeychainHelper.saveAPIKey(apiKey) {
                            keySaved = true
                            appState.refreshAPIKeyStatus()
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Divider().padding(.vertical, 4)

                Text("Optional: Gemini API key for text polishing")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                SecureField("Gemini API key (optional)", text: $geminiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                if geminiKeySaved {
                    Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if !geminiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Save Gemini Key") {
                        if KeychainHelper.saveGeminiKey(geminiKey) {
                            geminiKeySaved = true
                        }
                    }
                }
            }

            Link("Get an API key →", destination: URL(string: "https://elevenlabs.io/")!)
                .font(.caption)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick reference:")
                    .font(.headline)

                shortcutInfo("⌥ + -", "Quick capture → paste")
                shortcutInfo("⌥ + - + ⇧", "Translate → paste")
                shortcutInfo("⌥ + - + ⌘", "Capture → Obsidian")
                shortcutInfo("⌥ + - + ⌘ + ⇧", "Polish → Obsidian")
            }
            .padding(.horizontal, 32)

            Toggle("Launch Skrivar at login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))
            .padding(.horizontal, 64)
        }
    }

    // MARK: - Helpers

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.callout)
        }
    }

    private func permissionRow(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open") { action() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func shortcutInfo(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 140, alignment: .leading)
            Text(desc)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        dismiss()
        logger.info("Onboarding completed")
    }
}
