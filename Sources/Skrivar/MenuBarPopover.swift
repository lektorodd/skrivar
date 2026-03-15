import SwiftUI

/// Custom popover view for the menu bar, replacing the native system menu.
struct MenuBarPopover: View {
    @Bindable var appState: AppState
    var onOpenSettings: () -> Void
    var onEndSession: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            // Config summary
            configSummary
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // Shortcuts grid
            shortcutsGrid
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            // Raw session (if active)
            if appState.isRawSession {
                Divider()
                rawSessionSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            Divider()

            // Session stats
            sessionStats
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            // Actions footer
            actionsFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 8) {
            if appState.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.6), radius: 4)

                Text("\(appState.currentMode.rawValue) — Recording")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)

                Text(appState.statusMessage)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
    }

    // MARK: - Config Summary

    private var configSummary: some View {
        HStack(spacing: 12) {
            // Language
            Label(appState.languageDisplayName, systemImage: "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))

            // API Key status
            Label(
                appState.apiKeySet ? "✓" : "✗",
                systemImage: "key"
            )
            .font(.caption)
            .foregroundStyle(appState.apiKeySet ? .green : .red)

            // Obsidian
            if appState.obsidianConfigured {
                Label(
                    "\(appState.obsidianVaultName)/\(appState.obsidianFolder)",
                    systemImage: "book.closed"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer()
        }
    }

    // MARK: - Shortcuts Grid

    private var shortcutsGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                shortcutItem("⌃⌥", "Quick", .primary)
                shortcutItem("⌃⌥⇧", "Translate", Color(red: 0.0, green: 0.55, blue: 0.50))
            }
            HStack(spacing: 0) {
                shortcutItem("⌃⌥⌘", "Raw", Color(red: 0.75, green: 0.50, blue: 0.05))
                shortcutItem("⌃⌥⌘⇧", "Flash", Color(red: 0.85, green: 0.45, blue: 0.0))
            }
        }
    }

    private func shortcutItem(_ keys: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.7))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Raw Session

    private var rawSessionSection: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text("Raw session · \(appState.rawSessionChunkCount) chunks")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button("End") {
                onEndSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Session Stats

    private var sessionStats: some View {
        HStack(spacing: 12) {
            Label(
                "\(appState.sessionTranscriptions) transcriptions",
                systemImage: "waveform"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.7))

            if appState.sessionGeminiTokens > 0 {
                Label(
                    "\(appState.sessionGeminiTokens) tokens",
                    systemImage: "sparkles"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
            }

            Spacer()
        }
    }

    // MARK: - Actions Footer

    private var actionsFooter: some View {
        VStack(spacing: 8) {
            // Update banner
            if appState.updateAvailable {
                Button {
                    if let url = URL(string: appState.updateURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Update available: v\(appState.latestVersion)")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }

            HStack {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    onQuit()
                } label: {
                    Text("Quit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
