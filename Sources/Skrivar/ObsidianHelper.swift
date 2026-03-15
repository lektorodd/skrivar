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

    // MARK: - Raw Dictation helpers

    /// Create a new raw dictation note (opens in Obsidian foreground).
    /// Returns the file path for later appending, or nil on failure.
    static func createRawNote(vault: String, folder: String) -> String? {
        guard !vault.isEmpty else {
            logger.error("No Obsidian vault configured")
            return nil
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
            URLQueryItem(name: "content", value: "# Raw Thoughts\n\n"),
        ]

        guard let url = components.url else {
            logger.error("Failed to build Obsidian raw note URI")
            return nil
        }

        logger.info("Creating raw note: \(filePath)")
        NSWorkspace.shared.open(url)
        return filePath
    }

    /// Append text to an existing note in the vault.
    @discardableResult
    static func appendToNote(text: String, vault: String, file: String) -> Bool {
        guard !vault.isEmpty, !file.isEmpty else {
            logger.error("Missing vault or file for append")
            return false
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: file),
            URLQueryItem(name: "content", value: text),
            URLQueryItem(name: "append", value: "true"),
            URLQueryItem(name: "silent", value: "true"),
        ]

        guard let url = components.url else {
            logger.error("Failed to build Obsidian append URI")
            return false
        }

        logger.info("Appending to note: \(file)")
        NSWorkspace.shared.open(url)
        return true
    }
}
