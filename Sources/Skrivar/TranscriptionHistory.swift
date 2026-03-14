import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "History")

/// A single transcription entry.
struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mode: String
    let text: String
    let charCount: Int
    let wasPolished: Bool

    init(mode: CaptureMode, text: String, wasPolished: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.mode = mode.rawValue
        self.text = text
        self.charCount = text.count
        self.wasPolished = wasPolished
    }
}

/// Stores recent transcription history, persisted to UserDefaults.
@Observable
final class TranscriptionHistory {
    private static let storageKey = "transcriptionHistory"
    private static let maxEntries = 50

    var entries: [TranscriptionEntry] = []

    init() {
        load()
    }

    /// Add a new transcription entry.
    func add(mode: CaptureMode, text: String, wasPolished: Bool) {
        let entry = TranscriptionEntry(mode: mode, text: text, wasPolished: wasPolished)
        entries.insert(entry, at: 0)

        // Trim to max entries
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        save()
        logger.info("Saved transcription: \(text.prefix(40))… (\(text.count) chars)")
    }

    /// Clear all history.
    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
}
