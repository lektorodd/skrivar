import SwiftUI
import AppKit

/// Dynamic Island–style floating pill overlay with live waveform and mode-dependent styling.
final class OverlayPanel: NSPanel {
    private var hostingView: NSHostingView<OverlayContent>?
    private let overlayState = OverlayState()

    init() {
        let width: CGFloat = 260
        let height: CGFloat = 44

        // Center at bottom of main screen (above Dock)
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = (screen.frame.width - width) / 2
        let y: CGFloat = 80

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false

        let content = OverlayContent(state: overlayState)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        self.contentView = hosting
        self.hostingView = hosting
    }

    func show(mode: CaptureMode = .quick) {
        overlayState.mode = mode
        overlayState.statusText = "Listening…"
        overlayState.isVisible = true
        overlayState.recordingStart = Date()
        orderFrontRegardless()
    }

    func updateStatus(_ text: String) {
        overlayState.statusText = text
    }

    /// Update the audio level (0.0 – 1.0) for waveform visualization.
    func updateAudioLevel(_ level: Float) {
        overlayState.audioLevel = CGFloat(level)
    }

    func hide() {
        overlayState.isVisible = false
        overlayState.isError = false
        // Brief delay for exit animation — but only orderOut if still hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.overlayState.isVisible else { return }
            self.orderOut(nil)
        }
    }

    /// Show an error message in the overlay with red styling, auto-hides after 3s.
    func showError(_ message: String) {
        overlayState.statusText = message
        overlayState.isError = true
        overlayState.isVisible = true
        orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hide()
        }
    }
}

// MARK: - Observable State

@Observable
final class OverlayState {
    var mode: CaptureMode = .quick
    var statusText: String = "Listening…"
    var isVisible: Bool = false
    var isError: Bool = false
    var audioLevel: CGFloat = 0.0
    var recordingStart: Date = Date()
}

// MARK: - SwiftUI Overlay Content

struct OverlayContent: View {
    let state: OverlayState
    @State private var displayedLevels: [CGFloat] = Array(repeating: 0, count: 7)
    @State private var timer: Timer?
    @State private var elapsedSeconds: Int = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        ZStack {
            // Glassmorphism pill background
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: accentColor.opacity(0.3), radius: 10, y: 3)

            HStack(spacing: 10) {
                // Live waveform bars
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accentColor)
                            .frame(width: 3, height: barHeight(index: i))
                            .animation(.easeOut(duration: 0.08), value: displayedLevels[i])
                    }
                }
                .frame(height: 20)

                // Mode icon + status
                Text(modeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Recording timer
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .opacity(state.isVisible ? 1 : 0)
        .scaleEffect(state.isVisible ? 1 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.isVisible)
        .onAppear {
            startLevelSampling()
            startCountdown()
        }
        .onDisappear {
            stopLevelSampling()
            stopCountdown()
        }
        .onChange(of: state.isVisible) { _, visible in
            if visible {
                elapsedSeconds = 0
                startCountdown()
                startLevelSampling()
            } else {
                stopCountdown()
                stopLevelSampling()
            }
        }
    }

    // MARK: - Waveform

    private func barHeight(index: Int) -> CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 20
        return minH + displayedLevels[index] * (maxH - minH)
    }

    private func startLevelSampling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            updateLevels()
        }
    }

    private func stopLevelSampling() {
        timer?.invalidate()
        timer = nil
        displayedLevels = Array(repeating: 0, count: 7)
    }

    private func updateLevels() {
        let base = state.audioLevel
        var newLevels = displayedLevels
        // Shift levels left, add new level with slight random variation
        for i in 0..<(newLevels.count - 1) {
            newLevels[i] = newLevels[i + 1]
        }
        let jitter = CGFloat.random(in: -0.1...0.1)
        newLevels[newLevels.count - 1] = max(0, min(1, base + jitter))
        displayedLevels = newLevels
    }

    // MARK: - Timer

    private func startCountdown() {
        countdownTimer?.invalidate()
        elapsedSeconds = 0
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Colors

    private var accentColor: Color {
        if state.isError { return .red }
        switch state.mode {
        case .quick:       return .white
        case .translate:   return Color(red: 0, green: 0.82, blue: 0.70)   // Teal
        case .obsidianRaw: return Color(red: 0.95, green: 0.75, blue: 0.20) // Warm amber
        case .flash:       return Color(red: 1.0, green: 0.85, blue: 0.30)  // Bright gold
        }
    }

    private var modeLabel: String {
        switch state.mode {
        case .quick:       return state.statusText
        case .translate:   return "✦ \(state.statusText)"
        case .obsidianRaw: return "◉ \(state.statusText)"
        case .flash:       return "⚡ \(state.statusText)"
        }
    }
}
