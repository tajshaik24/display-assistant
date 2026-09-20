import Foundation
import ServiceManagement

/// Launch at login. The keyboard keys, Control Center controls and Siri actions all need the
/// app running, so it is switched on by default; the user can still turn it off in the panel.
enum LoginItem {
    private static let didEnableKey = "didEnableLaunchAtLogin"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// Registers once, and only for the installed copy, so development builds
    /// don't register themselves and a later opt-out is respected.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didEnableKey), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        do {
            try setEnabled(true)
            defaults.set(true, forKey: didEnableKey)
        } catch {
            // Left unset so the next launch tries again.
        }
    }
}
