import AppKit

/// Connects the keyboard's brightness and volume keys to the displays.
@MainActor
final class KeyboardController: ObservableObject {
    @Published private(set) var isActive = false

    private let store: DisplayStore
    private let tap = MediaKeyTap()
    private var trustPoll: Timer?

    init(store: DisplayStore) {
        self.store = store
        tap.ownsKey = { [weak self] key in self?.target(for: key) != nil }
        tap.handler = { [weak self] key, fine in self?.handle(key, fine: fine) }
        activate()
    }

    /// Asks for the Accessibility permission, then starts as soon as it is granted.
    func requestAccess() {
        MediaKeyTap.requestTrust()
        activate()
    }

    private func activate() {
        if MediaKeyTap.isTrusted, tap.start() {
            isActive = true
            trustPoll?.invalidate()
            trustPoll = nil
        } else if trustPoll == nil {
            // There is no notification for the permission being granted, so poll until it is.
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.activate() }
            }
        }
    }

    private func target(for key: MediaKey) -> DisplayModel? {
        switch key {
        case .brightnessUp, .brightnessDown:
            let target = store.targetDisplay(for: .brightness)
            // The key goes to macOS instead; if that moves a native display, synced displays should follow promptly.
            if target == nil { store.nativeBrightnessMayHaveChanged() }
            return target
        case .volumeUp, .volumeDown, .mute:
            // Only take the volume keys while sound is actually routed to a display.
            guard let deviceName = AudioOutput.displayDeviceName else { return nil }
            if let named = store.display(named: deviceName), named.supports(.volume) { return named }
            return store.commandTargets(for: .volume).first
        }
    }

    private func handle(_ key: MediaKey, fine: Bool) {
        guard let display = target(for: key) else { return }
        let step = fine ? KeyStep.fine : KeyStep.normal
        switch key {
        case .brightnessUp: display.step(.brightness, by: step)
        case .brightnessDown: display.step(.brightness, by: -step)
        case .volumeUp: display.step(.volume, by: step)
        case .volumeDown: display.step(.volume, by: -step)
        case .mute: display.setMuted(!display.isMuted)
        }
        switch key {
        case .brightnessUp, .brightnessDown: HUD.shared.show(.brightness, for: display)
        case .volumeUp, .volumeDown, .mute: HUD.shared.show(.volume, for: display)
        }
    }
}
