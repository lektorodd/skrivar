import SwiftUI
import AppKit

/// Dynamic Island–style floating pill overlay with mode-dependent styling.
final class OverlayPanel: NSPanel {
    private var hostingView: NSHostingView<OverlayContent>?
    private let overlayState = OverlayState()

    init() {
        let width: CGFloat = 220
        let height: CGFloat = 40

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
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false

        let content = OverlayContent(state: overlayState)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.contentView = hosting
        self.hostingView = hosting
    }

    func show(mode: CaptureMode = .quick) {
        overlayState.mode = mode
        overlayState.statusText = "Listening…"
        orderFrontRegardless()
    }

    func updateStatus(_ text: String) {
        overlayState.statusText = text
    }

    func hide() {
        orderOut(nil)
    }
}

// MARK: - Observable State

@Observable
final class OverlayState {
    var mode: CaptureMode = .quick
    var statusText: String = "Listening…"
}

// MARK: - SwiftUI Overlay Content

struct OverlayContent: View {
    let state: OverlayState
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            // Glassmorphism pill background
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.3), radius: 8, y: 2)

            HStack(spacing: 10) {
                // Pulsing dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(accentColor)
                            .frame(width: 7, height: 7)
                            .opacity(0.4 + 0.6 * pulseValue(index: i))
                            .scaleEffect(0.7 + 0.3 * pulseValue(index: i))
                    }
                }

                // Mode label
                Text(modeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1.0
            }
        }
    }

    private var accentColor: Color {
        switch state.mode {
        case .quick:            return .white
        case .translate:        return Color(red: 0, green: 0.82, blue: 0.70)   // Teal #00D1B2
        case .obsidian:         return Color(red: 0.49, green: 0.23, blue: 0.93) // Purple #7C3AED
        case .obsidianPolished: return Color(red: 0.40, green: 0.50, blue: 0.90) // Purple-teal blend
        }
    }

    private var modeLabel: String {
        switch state.mode {
        case .quick:            return state.statusText
        case .translate:        return "✦ \(state.statusText)"
        case .obsidian:         return "⬡ \(state.statusText)"
        case .obsidianPolished: return "⬡✦ \(state.statusText)"
        }
    }

    private func pulseValue(index: Int) -> CGFloat {
        let offset = CGFloat(index) * (2.0 / 3.0) * .pi
        return 0.5 + 0.5 * sin(phase * 2.0 * .pi + offset)
    }
}
