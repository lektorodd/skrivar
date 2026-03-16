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
/// Uses a configurable modifier combo (default: ⌃⌥) as the trigger.
final class KeyListener {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    var onRecordStart: ((CaptureMode) -> Void)?
    var onRecordStop: (() -> Void)?
    var onModeChange: ((CaptureMode) -> Void)?
    var onCancelPressed: (() -> Void)?
    private var isKeyDown = false
    private var activeMode: CaptureMode = .quick

    /// The modifier flags that trigger recording. Set from AppState.
    var triggerFlags: NSEvent.ModifierFlags = [.control, .option]

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

        // Monitor Escape key globally for cancel
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
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

    private func handleKeyDown(_ event: NSEvent) {
        // Escape key = keyCode 53
        if event.keyCode == 53 {
            DispatchQueue.main.async { [weak self] in
                self?.onCancelPressed?()
            }
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        let triggerActive = flags.contains(triggerFlags)

        if triggerActive && !isKeyDown {
            // Trigger pressed — start recording
            isKeyDown = true
            activeMode = computeMode(flags: flags)
            logger.info("Trigger pressed — mode: \(self.activeMode.rawValue)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onRecordStart?(self.activeMode)
            }
        } else if !triggerActive && isKeyDown {
            // Trigger released — stop recording
            isKeyDown = false
            logger.info("Trigger released — stopping (\(self.activeMode.rawValue))")
            DispatchQueue.main.async { [weak self] in
                self?.onRecordStop?()
            }
        } else if triggerActive && isKeyDown {
            // While recording, check if mode changed (extra modifiers toggled)
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

    /// Compute the capture mode from extra modifier flags beyond the trigger.
    private func computeMode(flags: NSEvent.ModifierFlags) -> CaptureMode {
        // Check for modifiers BEYOND the trigger combo
        let extraFlags = flags.subtracting(triggerFlags)
        let hasShift = extraFlags.contains(.shift)
        let hasCommand = extraFlags.contains(.command)
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
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        logger.info("Key monitor stopped")
    }
}
