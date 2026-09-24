import AppKit
import DisplayKit
import WidgetKit

/// Tracks controllable displays, routes commands to them and keeps their brightness in sync.
@MainActor
final class DisplayStore: ObservableObject {
    static let shared = DisplayStore()

    /// DDC monitors plus natively controlled displays. Anything that answers neither way is never shown or touched.
    @Published private(set) var displays: [DisplayModel] = []
    /// True while connected displays are still being queried for the first time.
    @Published private(set) var isLoading = false
    /// When on, every display is brought to the same brightness and they then move together.
    @Published var isSyncEnabled = UserDefaults.standard.bool(forKey: DisplayStore.syncKey) {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: Self.syncKey)
            alignSync()
        }
    }

    private var candidates: [DisplayModel] = []
    private var refreshTask: Task<Void, Never>?
    private var nativePoll: Timer?

    private var sync = BrightnessSync()

    private static let syncKey = "syncBrightness"
    private static let nativePollInterval: TimeInterval = 1.5

    private init() {
        refresh()

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Shared.commandNotification, object: nil, queue: .main) { [weak self] notification in
            let command = (notification.object as? String).flatMap { DisplayCommand($0) }
            MainActor.assumeIsolated {
                if let command { self?.perform(command) }
            }
        }
    }

    /// Sync needs at least two displays with brightness.
    var canSync: Bool { displays.filter { $0.supports(.brightness) }.count > 1 }

    // MARK: - Targeting

    /// The display a key press is meant for: the DDC monitor under the pointer, if it can do
    /// `control`. A pointer on any other screen (built-in, Studio Display, ...) means the system
    /// should handle the key, so this returns nil and the key passes through.
    func targetDisplay(for control: DisplayModel.Control) -> DisplayModel? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
            return commandTargets(for: control).first
        }
        let display = displays.first { $0.screen == screen }
        return display?.isNative == false && display?.supports(control) == true ? display : nil
    }

    /// Displays that commands without pointer context (Control Center, Siri, Shortcuts) act on:
    /// the DDC monitors, since macOS already covers the rest. With sync on, one is enough for
    /// brightness — the others follow.
    func commandTargets(for control: DisplayModel.Control) -> [DisplayModel] {
        let targets = displays.filter { !$0.isNative && $0.supports(control) }
        return control == .brightness && isSyncEnabled ? Array(targets.prefix(1)) : targets
    }

    func display(named name: String) -> DisplayModel? {
        displays.first { $0.name == name }
    }

    func perform(_ command: DisplayCommand) {
        let control: DisplayModel.Control
        switch command {
        case .showPanel:
            QuickPanel.shared.show()
            return
        case .setBrightness: control = .brightness
        case .setVolume, .mute, .unmute: control = .volume
        }
        let targets = commandTargets(for: control)
        for display in targets {
            switch command {
            case .setBrightness(let percent), .setVolume(let percent): display.set(control, to: Double(percent) / 100)
            case .mute: display.setMuted(true)
            case .unmute: display.setMuted(false)
            case .showPanel: break
            }
        }
        if let display = targets.first { HUD.shared.show(control, for: display) }
    }

    // MARK: - Sync

    /// Brings every display to the leader's brightness so they read the same from then on. The leader
    /// is the Apple display when there is one, since macOS moves it through auto-brightness and its keys.
    private func alignSync() {
        guard isSyncEnabled else { return }
        let synced = displays.filter { $0.supports(.brightness) }
        guard let leader = synced.first(where: \.isBuiltIn) ?? synced.first(where: \.isNative) ?? synced.first else { return }
        let level = leader.value(.brightness)
        for display in synced where display !== leader {
            display.set(.brightness, to: level, notify: false)
        }
        sync.align(synced.map(\.id), to: level)
    }

    private func brightnessChanged(on display: DisplayModel, from old: Double, to new: Double) {
        guard isSyncEnabled else { return }
        let targets = sync.change(display.id, from: old, to: new)
        for other in displays {
            guard let target = targets[other.id] else { continue }
            other.set(.brightness, to: target, notify: false)
        }
    }

    /// macOS has no public notification for brightness, so native displays are polled. Cheap: one float read each.
    private func updateNativePolling() {
        let needsPolling = displays.contains(where: \.isNative)
        if needsPolling, nativePoll == nil {
            nativePoll = Timer.scheduledTimer(withTimeInterval: Self.nativePollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollNativeDisplays() }
            }
        } else if !needsPolling {
            nativePoll?.invalidate()
            nativePoll = nil
        }
    }

    private func pollNativeDisplays() {
        for display in displays where display.isNative { display.refreshNativeBrightness() }
    }

    /// Called when a brightness key was left to macOS, so followers react without waiting for the next poll.
    func nativeBrightnessMayHaveChanged() {
        guard nativePoll != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.pollNativeDisplays()
        }
    }

    // MARK: - Discovery

    /// Displays need a moment after a reconfiguration or wake before DDC answers again.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        candidates = DisplayDiscovery.displays().map { display in
            let model = DisplayModel(display: display)
            model.onMuteChange = { [weak self] _ in self?.publishMuteState() }
            model.onLoad = { [weak self] in self?.publishControllable() }
            model.onBrightnessChange = { [weak self] display, old, new in self?.brightnessChanged(on: display, from: old, to: new) }
            return model
        }
        publishControllable()
    }

    private func publishControllable() {
        displays = candidates.filter(\.isControllable)
        isLoading = candidates.contains { !$0.isLoaded }
        alignSync()
        updateNativePolling()
        publishMuteState()
    }

    /// Lets actions that may have just launched the app wait for the displays to be queried.
    func waitUntilLoaded() async {
        for _ in 0..<40 where isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func publishMuteState() {
        let speakers = displays.filter { $0.supports(.volume) }
        let muted = !speakers.isEmpty && speakers.allSatisfy(\.isMuted)
        guard Shared.defaults.object(forKey: Shared.mutedKey) as? Bool != muted else { return }
        Shared.defaults.set(muted, forKey: Shared.mutedKey)
        ControlCenter.shared.reloadControls(ofKind: Shared.muteControlKind)
    }
}

enum KeyStep {
    /// macOS moves brightness and volume in sixteenths; ⌥⇧ gives quarter steps.
    static let normal = 1.0 / 16
    static let fine = 1.0 / 64
}
