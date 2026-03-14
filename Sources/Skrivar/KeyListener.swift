import Cocoa
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "KeyListener")

/// Capture modes determined by modifier keys held with Right Option.
enum CaptureMode: String {
    case quick            = "Quick"           // Right ⌥ only
    case translate        = "Translate"       // Right ⌥ + ⇧
    case obsidian         = "Obsidian"        // Right ⌥ + ⌘
    case obsidianPolished = "Obsidian+"       // Right ⌥ + ⌘ + ⇧
}

/// Global keyboard listener for Right Option key combos using CGEvent tap.
final class KeyListener {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onRecordStart: ((CaptureMode) -> Void)?
    var onRecordStop: (() -> Void)?
    /// Called when the mode changes while recording (e.g. Shift pressed after Right ⌥)
    var onModeChange: ((CaptureMode) -> Void)?
    private var isKeyDown = false
    private var activeMode: CaptureMode = .quick

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<KeyListener>.fromOpaque(refcon)
                    .takeUnretainedValue()
                return listener.handleEvent(event)
            },
            userInfo: refcon
        ) else {
            logger.error("Failed to create event tap — check Accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap started successfully")
    }

    /// Compute the capture mode from current modifier flags.
    private func computeMode(flags: CGEventFlags) -> CaptureMode {
        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)
        switch (hasCommand, hasShift) {
        case (true, true):   return .obsidianPolished
        case (true, false):  return .obsidian
        case (false, true):  return .translate
        case (false, false): return .quick
        }
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Right Option key (keyCode 61) — start/stop recording
        if keyCode == 61 {
            if flags.contains(.maskAlternate) && !isKeyDown {
                isKeyDown = true
                activeMode = computeMode(flags: flags)
                logger.info("Right Option pressed — mode: \(self.activeMode.rawValue)")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.onRecordStart?(self.activeMode)
                }
            } else if !flags.contains(.maskAlternate) && isKeyDown {
                isKeyDown = false
                logger.info("Right Option released — stopping (\(self.activeMode.rawValue))")
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordStop?()
                }
            }
        }

        // While recording, re-evaluate mode if Shift/Cmd changes
        // keyCodes: 56=LShift, 60=RShift, 55=LCmd, 54=RCmd
        if isKeyDown && (keyCode == 56 || keyCode == 60 || keyCode == 55 || keyCode == 54) {
            let newMode = computeMode(flags: flags)
            if newMode != activeMode {
                activeMode = newMode
                logger.info("Mode changed while recording → \(newMode.rawValue)")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.onModeChange?(self.activeMode)
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("Event tap stopped")
    }
}
