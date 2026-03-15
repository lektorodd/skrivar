import Cocoa
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "KeyListener")

/// Capture modes determined by modifier keys.
enum CaptureMode: String {
    case quick       = "Quick"           // Trigger alone
    case translate   = "Translate"       // Trigger + ⇧
    case obsidianRaw = "Raw"             // Trigger + ⌘
    case flash       = "Flash"           // Trigger + ⌘ + ⇧

    /// Priority for mode locking — higher value = more specific mode.
    /// Prevents accidental downgrade when modifier keys are released out of order.
    var priority: Int {
        switch self {
        case .quick: return 0
        case .translate: return 1
        case .obsidianRaw: return 2
        case .flash: return 3
        }
    }
}

/// Global keyboard listener using NSEvent monitors.
/// Uses Control+Option (⌃⌥) held together as the trigger — both are modifier keys
/// so no characters are produced, and it's an ergonomic right-hand combo.
final class KeyListener {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onRecordStart: ((CaptureMode) -> Void)?
    var onRecordStop: (() -> Void)?
    var onModeChange: ((CaptureMode) -> Void)?
    private var isKeyDown = false
    private var activeMode: CaptureMode = .quick

    /// Available trigger options for the settings UI.
    static let triggerKeyOptions: [(name: String, code: Int, display: String)] = [
        ("Control + Option (⌃⌥)", 0, "⌃⌥"),
    ]

    func start() {
        // Monitor modifier key changes globally
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }

        // Also monitor locally (when our own windows are focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }

        if globalMonitor != nil {
            print("[KeyListener] Global monitor started ✓")
            logger.info("Global key monitor started successfully")
        } else {
            print("[KeyListener] Failed to start global monitor — check Accessibility")
            logger.error("Failed to start global key monitor")
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        let triggerActive = flags.contains(.control) && flags.contains(.option)

        if triggerActive && !isKeyDown {
            // ⌃⌥ pressed — start recording
            isKeyDown = true
            activeMode = computeMode(flags: flags)
            print("[KeyListener] ⌃⌥ pressed — mode: \(activeMode.rawValue)")
            logger.info("⌃⌥ pressed — mode: \(self.activeMode.rawValue)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onRecordStart?(self.activeMode)
            }
        } else if !triggerActive && isKeyDown {
            // ⌃⌥ released — stop recording
            isKeyDown = false
            print("[KeyListener] ⌃⌥ released — stopping")
            logger.info("⌃⌥ released — stopping (\(self.activeMode.rawValue))")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordStop?()
            }
        } else if triggerActive && isKeyDown {
            // While recording, check if mode changed (Shift/Cmd toggled)
            let newMode = computeMode(flags: flags)
            if newMode != activeMode {
                activeMode = newMode
                logger.info("Mode changed → \(newMode.rawValue)")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.onModeChange?(self.activeMode)
                }
            }
        }
    }

    /// Compute the capture mode from current modifier flags.
    private func computeMode(flags: NSEvent.ModifierFlags) -> CaptureMode {
        let hasShift = flags.contains(.shift)
        let hasCommand = flags.contains(.command)
        switch (hasCommand, hasShift) {
        case (true, true):   return .flash
        case (true, false):  return .obsidianRaw
        case (false, true):  return .translate
        case (false, false): return .quick
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        logger.info("Key monitor stopped")
    }
}
