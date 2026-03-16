import Cocoa
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "TextInserter")

/// How text was inserted.
enum InsertionMethod: String {
    case accessibility = "AX API"
    case clipboard = "Clipboard"
}

/// Inserts text at the cursor: tries AX API first, falls back to clipboard paste.
/// Supports per-app rules to force a specific method.
enum TextInserter {

    /// Insert text at the current cursor position. Returns the method used.
    /// If `rules` contains a bundle ID match, that method is forced.
    @discardableResult
    static func insert(_ text: String, rules: [String: String] = [:]) -> InsertionMethod {
        // Check per-app rule
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleId = app.bundleIdentifier,
           let rule = rules[bundleId] {
            switch rule {
            case "accessibility":
                if insertViaAccessibility(text) {
                    logger.info("Inserted via AX API (rule) — \(app.localizedName ?? bundleId)")
                    return .accessibility
                }
                logger.info("AX rule failed, falling back to clipboard — \(app.localizedName ?? bundleId)")
                insertViaClipboard(text)
                return .clipboard
            case "clipboard":
                logger.info("Inserted via clipboard (rule) — \(app.localizedName ?? bundleId)")
                insertViaClipboard(text)
                return .clipboard
            default:
                break  // "auto" — fall through to normal behavior
            }
        }

        if insertViaAccessibility(text) {
            logger.info("Inserted via AX API (\(text.count) chars)")
            return .accessibility
        } else {
            logger.info("AX failed, using clipboard paste (\(text.count) chars)")
            insertViaClipboard(text)
            return .clipboard
        }
    }

    // MARK: - Accessibility API (primary)

    private static func insertViaAccessibility(_ text: String) -> Bool {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement
        )
        guard focusResult == .success, let element = focusedElement else {
            return false
        }

        let axElement = element as! AXUIElement

        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            axElement, kAXValueAttribute as CFString, &settable
        )
        guard settableResult == .success, settable.boolValue else {
            return false
        }

        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &currentValue
        )

        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange
        )

        if rangeResult == .success, let rangeValue = selectedRange {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                let currentStr = (currentValue as? String) ?? ""
                let nsStr = currentStr as NSString

                let before = nsStr.substring(to: range.location)
                let after = nsStr.substring(from: range.location + range.length)
                let newValue = before + text + after

                let setResult = AXUIElementSetAttributeValue(
                    axElement, kAXValueAttribute as CFString, newValue as CFTypeRef
                )

                if setResult == .success {
                    let newCursorPos = range.location + text.count
                    var newRange = CFRange(location: newCursorPos, length: 0)
                    if let rangeVal = AXValueCreate(.cfRange, &newRange) {
                        AXUIElementSetAttributeValue(
                            axElement,
                            kAXSelectedTextRangeAttribute as CFString,
                            rangeVal
                        )
                    }
                    return true
                }
            }
        }

        // Fallback: try setting the selected text directly
        let setSelectedResult = AXUIElementSetAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        return setSelectedResult == .success
    }

    // MARK: - Clipboard paste (fallback)

    private static func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save ALL pasteboard items (not just string) to preserve images, files, RTF, etc.
        let savedItems = savePasteboardContents(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        usleep(50_000)
        simulateCmdV()
        usleep(150_000)

        // Restore the full clipboard state
        restorePasteboardContents(pasteboard, items: savedItems)
    }

    /// Save all pasteboard items and their data for every type.
    private static func savePasteboardContents(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
    }

    /// Restore previously saved pasteboard items.
    private static func restorePasteboardContents(_ pasteboard: NSPasteboard, items: [[(NSPasteboard.PasteboardType, Data)]]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        let pasteboardItems = items.map { typeDataPairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typeDataPairs {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    private static func simulateCmdV() {
        guard let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else { return }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cgSessionEventTap)
        vUp.post(tap: .cgSessionEventTap)
    }
}
