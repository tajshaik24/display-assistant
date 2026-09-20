import AppKit
import DisplayKit
import SwiftUI

/// UI-facing state for one external display. Values are normalized to 0...1.
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

    @Published private(set) var values: [Control: Double] = [:]
    @Published private(set) var isMuted = false
    @Published private(set) var isLoaded = false

    /// Called whenever the mute state changes, so it can be mirrored to Control Center.
    var onMuteChange: ((Bool) -> Void)?
    /// Called each time the display has been queried, whether or not it answered.
    var onLoad: (() -> Void)?

    /// False for displays that don't speak DDC (or have it switched off); those are left alone.
    var isControllable: Bool { !values.isEmpty }

    private let writer: DDCWriter
    private var maxima: [Control: UInt16] = [:]
    private var supportsMute = false

    // A display that has just woken or been plugged in can take a few seconds to answer.
    private static let loadAttempts = 4
    private static let loadRetryDelay: Duration = .seconds(3)

    // DDC mute values per the MCCS spec.
    private static let muteOn: UInt16 = 1
    private static let muteOff: UInt16 = 2

    init(display: ExternalDisplay) {
        id = display.id
        name = display.name
        writer = DDCWriter(ddc: display.ddc, label: "DisplayAssistant.ddc.\(display.id)")
        load()
    }

    var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    func supports(_ control: Control) -> Bool { values[control] != nil }

    func value(_ control: Control) -> Double { values[control] ?? 0 }

    func set(_ control: Control, to newValue: Double) {
        guard let max = maxima[control] else { return }
        let clamped = min(1, Swift.max(0, newValue))
        let raw = UInt16((clamped * Double(max)).rounded())
        let changed = raw != UInt16((value(control) * Double(max)).rounded())
        values[control] = clamped
        if changed { writer.set(control.code, to: raw) }

        // Like macOS, touching the volume brings sound back.
        if control == .volume, isMuted, clamped > 0 { setMuted(false) }
    }

    func step(_ control: Control, by delta: Double) {
        set(control, to: value(control) + delta)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted, supportsMute || supports(.volume) else { return }
        isMuted = muted
        if supportsMute {
            writer.set(.mute, to: muted ? Self.muteOn : Self.muteOff)
        } else if let max = maxima[.volume] {
            // Displays without a mute command get their volume zeroed instead.
            writer.set(.volume, to: muted ? 0 : UInt16((value(.volume) * Double(max)).rounded()))
        }
        onMuteChange?(muted)
    }

    private func load(attempt: Int = 1) {
        writer.read(Control.allCases.map(\.code) + [.mute]) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                for control in Control.allCases {
                    guard let result = results[control.code], result.max > 0 else { continue }
                    self.maxima[control] = result.max
                    self.values[control] = Double(result.current) / Double(result.max)
                }
                if let mute = results[.mute] {
                    self.supportsMute = true
                    self.isMuted = mute.current == Self.muteOn
                }
                self.isLoaded = true
                self.onLoad?()

                if !self.isControllable, attempt < Self.loadAttempts {
                    Task { [weak self] in
                        try? await Task.sleep(for: Self.loadRetryDelay)
                        self?.load(attempt: attempt + 1)
                    }
                }
            }
        }
    }
}
