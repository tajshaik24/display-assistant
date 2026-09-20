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

enum DisplayCommand: Equatable {
    case mute, unmute
    /// Opens the slider panel, since Control Center itself cannot host sliders.
    case showPanel
    case setBrightness(percent: Int), setVolume(percent: Int)

    /// Wire format: the command name, then `:value` for the ones that carry a level.
    init?(_ string: String) {
        let parts = string.split(separator: ":", maxSplits: 1)
        let percent = parts.count > 1 ? Int(parts[1]).map { min(100, max(0, $0)) } : nil
        switch (parts.first, percent) {
        case ("mute", nil): self = .mute
        case ("unmute", nil): self = .unmute
        case ("showPanel", nil): self = .showPanel
        case ("setBrightness", let percent?): self = .setBrightness(percent: percent)
        case ("setVolume", let percent?): self = .setVolume(percent: percent)
        default: return nil
        }
    }

    var string: String {
        switch self {
        case .mute: "mute"
        case .unmute: "unmute"
        case .showPanel: "showPanel"
        case .setBrightness(let percent): "setBrightness:\(percent)"
        case .setVolume(let percent): "setVolume:\(percent)"
        }
    }

    /// Sandboxed processes may post distributed notifications only without userInfo,
    /// so the command travels in `object`.
    func post() {
        DistributedNotificationCenter.default().postNotificationName(
            Shared.commandNotification, object: string, userInfo: nil, deliverImmediately: true
        )
    }
}
