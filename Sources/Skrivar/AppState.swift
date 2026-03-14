import SwiftUI

/// Shared application state using @Observable (macOS 14+).
@Observable
final class AppState {
    var isRecording = false
    var currentMode: CaptureMode = .quick
    var pendingRecordTask: DispatchWorkItem?
    var statusMessage = "Ready"
    var apiKeySet = false
    var geminiEnabled: Bool {
        didSet { UserDefaults.standard.set(geminiEnabled, forKey: "geminiEnabled") }
    }
    var geminiTargetLanguage: String {
        didSet { UserDefaults.standard.set(geminiTargetLanguage, forKey: "geminiTargetLanguage") }
    }
    var languageCode: String {
        didSet { UserDefaults.standard.set(languageCode, forKey: "languageCode") }
    }

    // MARK: - Obsidian settings

    var obsidianVaultName: String {
        didSet { UserDefaults.standard.set(obsidianVaultName, forKey: "obsidianVaultName") }
    }
    var obsidianFolder: String {
        didSet { UserDefaults.standard.set(obsidianFolder, forKey: "obsidianFolder") }
    }

    /// UID of the selected audio input device (empty = system default)
    var audioInputDeviceUID: String {
        didSet { UserDefaults.standard.set(audioInputDeviceUID, forKey: "audioInputDeviceUID") }
    }

    // MARK: - Session stats

    var sessionTranscriptions = 0
    var sessionGeminiTokens = 0
    var lastInsertionMethod: InsertionMethod?
    var lastGeminiUsage: GeminiUsage?

    // MARK: - Persistent all-time stats

    var totalTranscriptions: Int {
        didSet { UserDefaults.standard.set(totalTranscriptions, forKey: "totalTranscriptions") }
    }
    var totalCharacters: Int {
        didSet { UserDefaults.standard.set(totalCharacters, forKey: "totalCharacters") }
    }
    var totalGeminiTokens: Int {
        didSet { UserDefaults.standard.set(totalGeminiTokens, forKey: "totalGeminiTokens") }
    }

    var hasGeminiKey: Bool {
        guard let key = KeychainHelper.loadGeminiKey() else { return false }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Supported languages (display name → ElevenLabs code)
    static let languages: [(name: String, code: String)] = [
        ("Norsk", "nor"),
        ("English", "eng"),
        ("Deutsch", "deu"),
        ("Français", "fra"),
        ("Español", "spa"),
        ("Auto-detect", ""),
    ]

    /// Target languages for Gemini polishing
    static let geminiLanguages: [(name: String, code: String)] = [
        ("Nynorsk", "nynorsk"),
        ("Bokmål", "bokmål"),
        ("English", "english"),
        ("Deutsch", "deutsch"),
        ("Same as input", "same"),
    ]

    init() {
        var saved = UserDefaults.standard.string(forKey: "languageCode") ?? "nor"
        if saved == "nno" || saved == "nob" { saved = "nor" }
        self.languageCode = saved
        self.geminiEnabled = UserDefaults.standard.bool(forKey: "geminiEnabled")
        self.geminiTargetLanguage = UserDefaults.standard.string(forKey: "geminiTargetLanguage") ?? "nynorsk"
        self.obsidianVaultName = UserDefaults.standard.string(forKey: "obsidianVaultName") ?? ""
        self.obsidianFolder = UserDefaults.standard.string(forKey: "obsidianFolder") ?? "Inbox"
        self.audioInputDeviceUID = UserDefaults.standard.string(forKey: "audioInputDeviceUID") ?? ""
        self.totalTranscriptions = UserDefaults.standard.integer(forKey: "totalTranscriptions")
        self.totalCharacters = UserDefaults.standard.integer(forKey: "totalCharacters")
        self.totalGeminiTokens = UserDefaults.standard.integer(forKey: "totalGeminiTokens")
        self.apiKeySet = KeychainHelper.hasAPIKey()
    }

    func refreshAPIKeyStatus() {
        apiKeySet = KeychainHelper.hasAPIKey()
    }

    func recordTranscription(chars: Int, method: InsertionMethod?, geminiUsage: GeminiUsage?) {
        sessionTranscriptions += 1
        totalTranscriptions += 1
        totalCharacters += chars
        lastInsertionMethod = method
        if let usage = geminiUsage {
            lastGeminiUsage = usage
            sessionGeminiTokens += usage.totalTokens
            totalGeminiTokens += usage.totalTokens
        }
    }

    func resetAllTimeStats() {
        totalTranscriptions = 0
        totalCharacters = 0
        totalGeminiTokens = 0
    }

    var languageDisplayName: String {
        Self.languages.first(where: { $0.code == languageCode })?.name ?? "Auto-detect"
    }

    var geminiTargetDisplayName: String {
        Self.geminiLanguages.first(where: { $0.code == geminiTargetLanguage })?.name ?? geminiTargetLanguage
    }

    var obsidianConfigured: Bool {
        !obsidianVaultName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
