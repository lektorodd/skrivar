import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "UpdateChecker")

/// Checks GitHub Releases for a newer version of Skrivar (once per launch).
enum UpdateChecker {

    /// GitHub owner/repo for release lookups.
    private static let repo = "lektorodd/skrivar"

    /// Check for updates and update the provided AppState if a newer version is found.
    static func check(appState: AppState) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                logger.warning("Update check failed: \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                logger.debug("Could not parse release response")
                return
            }

            // Strip leading "v" from tag (e.g. "v0.4.0" → "0.4.0")
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            // Dev builds (version 0.0.0) are always ahead of releases — skip check
            guard currentVersion != "0.0.0" else {
                logger.debug("Dev build detected, skipping update check")
                return
            }

            logger.info("Current: \(currentVersion), Latest: \(remoteVersion)")

            if isNewer(remote: remoteVersion, current: currentVersion) {
                DispatchQueue.main.async {
                    appState.updateAvailable = true
                    appState.latestVersion = remoteVersion
                    appState.updateURL = htmlURL
                    logger.info("Update available: \(remoteVersion)")
                }
            }
        }.resume()
    }

    /// Simple semantic version comparison: returns true if remote > current.
    private static func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
