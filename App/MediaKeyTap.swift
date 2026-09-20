import AppKit
import ApplicationServices

enum MediaKey {
    case brightnessUp, brightnessDown, volumeUp, volumeDown, mute

    // NX_KEYTYPE_* values from IOKit's ev_keymap.h.
    init?(keyCode: Int) {
        switch keyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        case 7: self = .mute
        default: return nil
        }
    }
}

/// Intercepts the keyboard's brightness and volume keys. Requires the Accessibility permission.
@MainActor
final class MediaKeyTap {
    /// Decides whether a key should be taken from the system right now.
    var ownsKey: ((MediaKey) -> Bool)?
    /// Performs the action for an owned key. `fine` is true while ⌥⇧ is held.
    var handler: ((_ key: MediaKey, _ fine: Bool) -> Void)?

    private var tap: CFMachPort?

    private static let systemDefinedEventType: UInt32 = 14
    private static let mediaKeySubtype: Int16 = 8

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap's run loop source lives on the main run loop.
            return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefinedEventType,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.mediaKeySubtype,
              let key = MediaKey(keyCode: (nsEvent.data1 & 0xFFFF_0000) >> 16)
        else { return Unmanaged.passUnretained(event) }

        guard ownsKey?(key) == true else { return Unmanaged.passUnretained(event) }

        // Swallow key-up along with key-down, but only act once per press (repeats arrive as key-downs).
        let isKeyDown = (nsEvent.data1 & 0xFF00) >> 8 == 0xA
        if isKeyDown {
            handler?(key, nsEvent.modifierFlags.isSuperset(of: [.option, .shift]))
        }
        return nil
    }
}
