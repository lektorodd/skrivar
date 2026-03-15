import Foundation
import Security

/// Thin wrapper around Security.framework for API key storage in macOS Keychain.
enum KeychainHelper {
    private static let service = "com.skrivar.app"
    private static let apiKeyAccount = "elevenlabs_api_key"
    private static let geminiKeyAccount = "gemini_api_key"

    // MARK: - ElevenLabs API Key

    static func saveAPIKey(_ key: String) -> Bool {
        save(account: apiKeyAccount, value: key)
    }

    static func loadAPIKey() -> String? {
        load(account: apiKeyAccount)
    }

    static func hasAPIKey() -> Bool {
        guard let key = loadAPIKey() else { return false }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Gemini API Key

    static func saveGeminiKey(_ key: String) -> Bool {
        save(account: geminiKeyAccount, value: key)
    }

    static func loadGeminiKey() -> String? {
        load(account: geminiKeyAccount)
    }

    // MARK: - Generic Helpers

    private static func save(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
