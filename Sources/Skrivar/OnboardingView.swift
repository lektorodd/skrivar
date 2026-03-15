import SwiftUI
import AVFoundation
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

    // Live permission status
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var permissionTimer: Timer?

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
                } else {
                    Button("Start Using Skrivar") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            checkPermissions()
            startPermissionPolling()
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Permission Polling

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            checkPermissions()
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = false
        default:
            microphoneGranted = false
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to Skrivar")
                .font(.title.weight(.semibold))

            Text("Speech-to-text for your Mac.\nHold **⌃⌥** (Control + Option) to record, release to transcribe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

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
                    granted: accessibilityGranted,
                    action: {
                        // Trigger the system prompt dialog
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                )

                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "To record audio for transcription",
                    granted: microphoneGranted,
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            DispatchQueue.main.async {
                                microphoneGranted = granted
                            }
                        }
                    }
                )
            }
            .padding(.horizontal, 24)

            // Update warning
            VStack(spacing: 4) {
                Text("⚠️ After updating Skrivar, you may need to re-grant\nAccessibility permission in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)

                Text("This is a macOS requirement for unsigned apps.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("API Keys")
                .font(.title2.weight(.semibold))

            Text("Enter your API keys. macOS may ask you to allow\nKeychain access — click **Always Allow**.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.callout)

            VStack(spacing: 12) {
                // ElevenLabs key
                VStack(alignment: .leading, spacing: 4) {
                    Text("ElevenLabs (required)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    SecureField("ElevenLabs API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)

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
                }

                Divider().padding(.vertical, 2)

                // Gemini key
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini (optional — for Translate & Flash)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    SecureField("Gemini API key", text: $geminiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)

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
            }

            HStack(spacing: 16) {
                Link("ElevenLabs key →", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                    .font(.caption)
                Link("Gemini key →", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            }
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

                shortcutInfo("⌃⌥", "Quick capture → paste")
                shortcutInfo("⌃⌥⇧", "Translate → paste")
                shortcutInfo("⌃⌥⌘", "Raw Dictation → Obsidian")
                shortcutInfo("⌃⌥⌘⇧", "Flash (synthesize session)")
            }
            .padding(.horizontal, 32)

            Text("Hold **Control + Option** to record, release to transcribe.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

    private func permissionRow(icon: String, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(granted ? .green : .red.opacity(0.7))
                        .font(.caption)
                }
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func shortcutInfo(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            Text(desc)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        logger.info("Onboarding completed")
        // Notify the app to start deferred subsystems
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}
