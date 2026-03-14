import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "Obsidian")

/// Creates notes in an Obsidian vault using the obsidian:// URI scheme.
enum ObsidianHelper {

    /// Create a new note in the configured Obsidian vault.
    /// - Parameters:
    ///   - text: The note content
    ///   - vault: The Obsidian vault name
    ///   - folder: Folder within the vault (e.g. "Inbox")
    /// - Returns: `true` if the URI was opened successfully
    @discardableResult
    static func createNote(text: String, vault: String, folder: String) -> Bool {
        guard !vault.isEmpty else {
            logger.error("No Obsidian vault configured")
            return false
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = dateFormatter.string(from: Date())

        let filePath = folder.isEmpty ? timestamp : "\(folder)/\(timestamp)"

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: filePath),
            URLQueryItem(name: "content", value: text),
            URLQueryItem(name: "silent", value: "true"),
        ]

        guard let url = components.url else {
            logger.error("Failed to build Obsidian URI")
            return false
        }

        logger.info("Opening Obsidian: \(url.absoluteString.prefix(80))")
        NSWorkspace.shared.open(url)
        return true
    }
}
