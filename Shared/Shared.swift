import Foundation

/// State and commands shared between the app and its Control Center extension.
///
/// The extension is sandboxed and cannot talk to the display itself, so it posts a
/// command to the (always running) app and reads back state from the app group.
enum Shared {
    static let appGroup = "LDUCPMFSMH.com.tajshaik.DisplayAssistant"
    static let commandNotification = Notification.Name("com.tajshaik.DisplayAssistant.command")
    static let mutedKey = "muted"
    static let muteControlKind = "com.tajshaik.DisplayAssistant.control.mute"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

enum DisplayCommand: String {
    case brightnessUp, brightnessDown, volumeUp, volumeDown, mute, unmute

    /// Sandboxed processes may post distributed notifications only without userInfo,
    /// so the command travels in `object`.
    func post() {
        DistributedNotificationCenter.default().postNotificationName(
            Shared.commandNotification, object: rawValue, userInfo: nil, deliverImmediately: true
        )
    }
}
