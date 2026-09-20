import AppKit
import DisplayKit
import WidgetKit

/// Tracks connected external displays and routes commands to them.
@MainActor
final class DisplayStore: ObservableObject {
    static let shared = DisplayStore()

    /// Displays that answer DDC. Anything else (no DDC, or natively controlled) is never shown or touched.
    @Published private(set) var displays: [DisplayModel] = []
    /// True while connected displays are still being queried for the first time.
    @Published private(set) var isLoading = false

    private var candidates: [DisplayModel] = []
    private var refreshTask: Task<Void, Never>?

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
            let command = (notification.object as? String).flatMap(DisplayCommand.init)
            MainActor.assumeIsolated {
                if let command { self?.perform(command) }
            }
        }
    }

    /// The display a key press is meant for: the one under the pointer, if it is ours and
    /// can do `control`. A pointer on any other screen (built-in, Studio Display, ...) means
    /// the system should handle the key, so this returns nil and the key passes through.
    func targetDisplay(for control: DisplayModel.Control) -> DisplayModel? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
            return firstDisplay(supporting: control)
        }
        let display = displays.first { $0.screen == screen }
        return display?.supports(control) == true ? display : nil
    }

    func firstDisplay(supporting control: DisplayModel.Control) -> DisplayModel? {
        displays.first { $0.supports(control) }
    }

    func display(named name: String) -> DisplayModel? {
        displays.first { $0.name == name }
    }

    /// Commands from Control Center carry no pointer context, so they apply to every display.
    func perform(_ command: DisplayCommand) {
        for display in displays {
            switch command {
            case .brightnessUp: display.step(.brightness, by: KeyStep.normal)
            case .brightnessDown: display.step(.brightness, by: -KeyStep.normal)
            case .volumeUp: display.step(.volume, by: KeyStep.normal)
            case .volumeDown: display.step(.volume, by: -KeyStep.normal)
            case .mute: display.setMuted(true)
            case .unmute: display.setMuted(false)
            }
        }
        let control: DisplayModel.Control = switch command {
        case .brightnessUp, .brightnessDown: .brightness
        case .volumeUp, .volumeDown, .mute, .unmute: .volume
        }
        if let display = firstDisplay(supporting: control) { HUD.shared.show(control, for: display) }
    }

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
        candidates = DisplayDiscovery.externalDisplays().map { display in
            let model = DisplayModel(display: display)
            model.onMuteChange = { [weak self] _ in self?.publishMuteState() }
            model.onLoad = { [weak self] in self?.publishControllable() }
            return model
        }
        publishControllable()
    }

    private func publishControllable() {
        displays = candidates.filter(\.isControllable)
        isLoading = candidates.contains { !$0.isLoaded }
        publishMuteState()
    }

    /// Lets actions that may have just launched the app wait for the displays to be queried.
    func waitUntilLoaded() async {
        for _ in 0..<40 where isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func publishMuteState() {
        let muted = !displays.isEmpty && displays.allSatisfy(\.isMuted)
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
