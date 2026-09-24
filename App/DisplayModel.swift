import AppKit
import DisplayKit
import SwiftUI

/// UI-facing state for one display. Values are normalized to 0...1.
@MainActor
final class DisplayModel: ObservableObject, Identifiable {
    enum Control: CaseIterable {
        case brightness, volume

        var code: VCPCode {
            switch self {
            case .brightness: .brightness
            case .volume: .volume
            }
        }
    }

    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    /// True for displays macOS controls itself (built-in, Studio Display, ...). They only offer
    /// brightness here, and their keys and volume stay with the system.
    let isNative: Bool

    @Published private(set) var values: [Control: Double] = [:]
    @Published private(set) var isMuted = false
    @Published private(set) var isLoaded = false

    /// Called whenever the mute state changes, so it can be mirrored to Control Center.
    var onMuteChange: ((Bool) -> Void)?
    /// Called each time the display has been queried, whether or not it answered.
    var onLoad: (() -> Void)?
    /// Called with the old and new brightness when it changes for any reason other than sync
    /// itself: the user, a command, or (for native displays) macOS.
    var onBrightnessChange: ((DisplayModel, Double, Double) -> Void)?

    /// False for displays that answer neither way; those are left alone.
    var isControllable: Bool { !values.isEmpty }

    /// Nil for native displays.
    private let writer: DDCWriter?
    private var maxima: [Control: UInt16] = [:]
    private var supportsMute = false

    private var isReading = false
    private var readWaiters: [() -> Void] = []
    /// Bumped on every local change, so a read that was in flight meanwhile doesn't undo it.
    private var localChanges = 0
    /// When the values were last known to match the monitor: read from it, or written by us.
    private var lastSynced: ContinuousClock.Instant?

    // A display that has just woken or been plugged in can take a few seconds to answer.
    private static let loadAttempts = 4
    private static let loadRetryDelay: Duration = .seconds(3)

    /// Smallest native brightness movement treated as a real change rather than rounding.
    private static let nativeChangeThreshold = 0.015

    // DDC mute values per the MCCS spec.
    private static let muteOn: UInt16 = 1
    private static let muteOff: UInt16 = 2

    init(display: ControllableDisplay) {
        id = display.id
        name = display.name
        isBuiltIn = display.isBuiltIn
        switch display.backend {
        case .ddc(let channel):
            isNative = false
            writer = DDCWriter(ddc: channel, label: "DisplayAssistant.ddc.\(display.id)")
            loadDDC()
        case .native:
            isNative = true
            writer = nil
            values[.brightness] = NativeBrightness.get(display.id)
            isLoaded = true
        }
    }

    var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    func supports(_ control: Control) -> Bool { values[control] != nil }

    func value(_ control: Control) -> Double { values[control] ?? 0 }

    /// - Parameter notify: false when sync is applying another display's change, so it doesn't echo back.
    func set(_ control: Control, to newValue: Double, notify: Bool = true) {
        guard supports(control) else { return }
        let old = value(control)
        let new = min(1, max(0, newValue))
        values[control] = new
        write(control, old: old, new: new)
        noteLocalChange()

        // Like macOS, touching the volume brings sound back.
        if control == .volume, isMuted, new > 0 { setMuted(false) }
        if control == .brightness, notify, new != old { onBrightnessChange?(self, old, new) }
    }

    func step(_ control: Control, by delta: Double) {
        set(control, to: value(control) + delta)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted, let writer, supportsMute || supports(.volume) else { return }
        isMuted = muted
        noteLocalChange()
        if supportsMute {
            writer.set(.mute, to: muted ? Self.muteOn : Self.muteOff)
        } else if let max = maxima[.volume] {
            // Displays without a mute command get their volume zeroed instead.
            writer.set(.volume, to: muted ? 0 : UInt16((value(.volume) * Double(max)).rounded()))
        }
        onMuteChange?(muted)
    }

    /// Re-reads the monitor to pick up changes made with its own buttons, then calls `completion`.
    /// Values read or written within `maxAge` are trusted as they are.
    func refresh(ifOlderThan maxAge: Duration = .zero, then completion: (() -> Void)? = nil) {
        if isNative {
            refreshNativeBrightness()
            completion?()
        } else if let lastSynced, ContinuousClock.now - lastSynced < maxAge {
            completion?()
        } else {
            readDDC(then: completion)
        }
    }

    func refresh(ifOlderThan maxAge: Duration = .zero) async {
        await withCheckedContinuation { continuation in
            refresh(ifOlderThan: maxAge) { continuation.resume() }
        }
    }

    /// Picks up brightness changes made outside the app: auto-brightness, the native keys, Control Center.
    func refreshNativeBrightness() {
        guard isNative, let current = NativeBrightness.get(id) else { return }
        let old = value(.brightness)
        guard abs(current - old) > Self.nativeChangeThreshold else { return }
        values[.brightness] = current
        onBrightnessChange?(self, old, current)
    }

    private func write(_ control: Control, old: Double, new: Double) {
        if let writer, let max = maxima[control] {
            // Only talk to the monitor when its own (coarser) scale actually moves.
            let raw = UInt16((new * Double(max)).rounded())
            if raw != UInt16((old * Double(max)).rounded()) { writer.set(control.code, to: raw) }
        } else if isNative, control == .brightness {
            NativeBrightness.set(id, to: new)
        }
    }

    private func noteLocalChange() {
        localChanges += 1
        lastSynced = .now
    }

    private func loadDDC(attempt: Int = 1) {
        readDDC { [weak self] in
            guard let self else { return }
            self.isLoaded = true
            self.onLoad?()

            if !self.isControllable, attempt < Self.loadAttempts {
                Task { [weak self] in
                    try? await Task.sleep(for: Self.loadRetryDelay)
                    self?.loadDDC(attempt: attempt + 1)
                }
            }
        }
    }

    /// Reads every control from the monitor. Calls made while a read is in flight share its result.
    private func readDDC(then completion: (() -> Void)?) {
        guard let writer else {
            completion?()
            return
        }
        if let completion { readWaiters.append(completion) }
        guard !isReading else { return }
        isReading = true
        let changesAtStart = localChanges
        writer.read(Control.allCases.map(\.code) + [.mute]) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                if self.localChanges == changesAtStart, !results.isEmpty {
                    self.apply(results)
                    self.lastSynced = .now
                }
                let waiters = self.readWaiters
                self.readWaiters = []
                for waiter in waiters { waiter() }
            }
        }
    }

    private func apply(_ results: [VCPCode: VCPValue]) {
        if let mute = results[.mute] {
            supportsMute = true
            setMutedFromMonitor(mute.current == Self.muteOn)
        }
        for control in Control.allCases {
            guard let result = results[control.code], result.max > 0 else { continue }
            maxima[control] = result.max
            let old = values[control]
            // Keep our finer value while it still maps to what the monitor reports.
            if let old, UInt16((old * Double(result.max)).rounded()) == result.current { continue }
            if control == .volume, isMuted, !supportsMute {
                // Muted by zeroing the volume: keep the level to restore, unless it was turned up on the monitor.
                guard result.current > 0 else { continue }
                setMutedFromMonitor(false)
            }
            let new = Double(result.current) / Double(result.max)
            values[control] = new
            if control == .brightness, let old { onBrightnessChange?(self, old, new) }
        }
    }

    private func setMutedFromMonitor(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        onMuteChange?(muted)
    }
}
