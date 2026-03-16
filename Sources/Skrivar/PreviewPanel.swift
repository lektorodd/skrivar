import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "PreviewPanel")

/// Utility-style floating preview panel that respects system appearance.
/// Uses .titled + .utilityWindow + .nonactivatingPanel (no .hudWindow = respects light/dark mode).
final class PreviewPanel: NSPanel {
    private var hostingView: NSHostingView<PreviewContent>?
    private let previewState = PreviewState()

    /// Called when user confirms paste (with potentially edited text).
    var onPaste: ((String) -> Void)?
    /// Called when user discards.
    var onDiscard: (() -> Void)?

    /// The app that was frontmost before showing the preview.
    private var previousApp: NSRunningApplication?

    override var canBecomeKey: Bool { true }

    init() {
        let width: CGFloat = 420
        let height: CGFloat = 220

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.title = "Preview"
        self.level = .floating
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        let content = PreviewContent(
            state: previewState,
            onPaste: { [weak self] text in self?.handlePaste(text) },
            onDiscard: { [weak self] in self?.handleDiscard() },
            onEdit: { [weak self] in self?.handleEditToggle() }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.contentView = hosting
        self.hostingView = hosting
    }

    func show(text: String, autoPasteSeconds: Int = 5) {
        logger.info("PreviewPanel.show() — \(text.count) chars")

        previousApp = NSWorkspace.shared.frontmostApplication

        previewState.text = text
        previewState.editedText = text
        previewState.isEditing = false
        previewState.countdown = autoPasteSeconds
        previewState.isVisible = true
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        previewState.startCountdown { [weak self] in
            self?.handlePaste(self?.previewState.editedText ?? text)
        }
    }

    func dismiss() {
        previewState.stopCountdown()
        previewState.isVisible = false
        orderOut(nil)
    }

    private func handlePaste(_ text: String) {
        guard previewState.isVisible else { return }
        logger.info("Preview: pasting \(text.count) chars")
        dismiss()

        if let app = previousApp {
            app.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.onPaste?(text)
        }
    }

    private func handleDiscard() {
        guard previewState.isVisible else { return }
        logger.info("Preview: discarded")
        dismiss()

        if let app = previousApp {
            app.activate()
        }
        onDiscard?()
    }

    private func handleEditToggle() {
        previewState.isEditing.toggle()
        if previewState.isEditing {
            previewState.stopCountdown()
        }
    }
}

// MARK: - Observable State

@Observable
final class PreviewState {
    var text: String = ""
    var editedText: String = ""
    var isEditing: Bool = false
    var countdown: Int = 5
    var isVisible: Bool = false
    private var timer: Timer?

    func startCountdown(onComplete: @escaping () -> Void) {
        stopCountdown()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdown -= 1
            if self.countdown <= 0 {
                self.stopCountdown()
                onComplete()
            }
        }
    }

    func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - SwiftUI Content

struct PreviewContent: View {
    let state: PreviewState
    let onPaste: (String) -> Void
    let onDiscard: () -> Void
    let onEdit: () -> Void
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status hint
            HStack(spacing: 4) {
                if state.isEditing {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                    Text("⌘E done · ⏎ paste")
                        .foregroundStyle(.orange)
                } else if state.countdown > 0 {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    Text("⏎ paste · ⎋ discard · \(state.countdown)s")
                        .foregroundStyle(.secondary)
                } else {
                    Text("⏎ paste · ⎋ discard")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))

            // Text area — uses TextField for single-line or TextEditor for multiline
            Group {
                if state.isEditing {
                    // Use a plain NSTextView wrapper that treats Enter as "submit"
                    PasteOnEnterEditor(
                        text: Binding(
                            get: { state.editedText },
                            set: { state.editedText = $0 }
                        ),
                        isFocused: $editorFocused,
                        onSubmit: { onPaste(state.editedText) }
                    )
                } else {
                    ScrollView {
                        Text(state.editedText)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )

            // Buttons
            HStack(spacing: 8) {
                Button(action: { onDiscard() }) {
                    Label("Discard", systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { onEdit() }) {
                    Label(state.isEditing ? "Done" : "Edit", systemImage: state.isEditing ? "checkmark" : "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: {
                    if state.isEditing { state.isEditing = false }
                    onPaste(state.editedText)
                }) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .onChange(of: state.isEditing) { _, editing in
            if editing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    editorFocused = true
                }
            }
        }
    }
}

// MARK: - Custom Editor that treats Enter as "submit" (not newline)

struct PasteOnEnterEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        // Auto-focus
        if isFocused.wrappedValue {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: PasteOnEnterEditor

        init(_ parent: PasteOnEnterEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        // Intercept Enter key — treat as submit, not newline
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true  // We handled it
            }
            return false  // Let other commands through
        }
    }
}
