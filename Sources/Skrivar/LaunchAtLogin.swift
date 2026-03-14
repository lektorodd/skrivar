import Foundation
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "LaunchAtLogin")

/// Manages Launch at Login via SMAppService (macOS 13+).
enum LaunchAtLogin {

    /// Whether the app is registered to launch at login.
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    logger.info("Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    logger.info("Launch at login disabled")
                }
            } catch {
                logger.error("Failed to update launch at login: \(error.localizedDescription)")
            }
        }
    }
}
