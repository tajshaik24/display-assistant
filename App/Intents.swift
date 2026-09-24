import AppIntents

// Actions for Siri, Shortcuts and Spotlight. They run inside the app (launching it in the
// background if needed) and act on the DDC monitors, like the Control Center controls.

enum DisplayIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noDisplay(DisplayModel.Control)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDisplay(.brightness): "No connected display supports brightness control."
        case .noDisplay(.volume): "No connected display supports volume control."
        }
    }
}

@MainActor
private func displays(supporting control: DisplayModel.Control) async throws -> [DisplayModel] {
    let store = DisplayStore.shared
    await store.waitUntilLoaded()
    let displays = store.commandTargets(for: control)
    guard !displays.isEmpty else { throw DisplayIntentError.noDisplay(control) }
    // Report and toggle from what the monitors say now, not what they said when the app last looked.
    for display in displays { await display.refresh() }
    return displays
}

@MainActor
private func set(_ control: DisplayModel.Control, toPercent percent: Int) async throws {
    let displays = try await displays(supporting: control)
    for display in displays { display.set(control, to: Double(percent) / 100) }
    HUD.shared.show(control, for: displays[0])
}

@MainActor
private func percent(of control: DisplayModel.Control) async throws -> Int {
    Int((try await displays(supporting: control)[0].value(control) * 100).rounded())
}

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Brightness"
    static let description = IntentDescription("Sets the brightness of your external display.")

    @Parameter(title: "Brightness", inclusiveRange: (0, 100), requestValueDialog: "What brightness, from 0 to 100?")
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set display brightness to \(\.$percent)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await set(.brightness, toPercent: percent)
        return .result(dialog: "Display brightness set to \(percent)%.")
    }
}

struct SetVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Volume"
    static let description = IntentDescription("Sets the speaker volume of your external display.")

    @Parameter(title: "Volume", inclusiveRange: (0, 100), requestValueDialog: "What volume, from 0 to 100?")
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set display volume to \(\.$percent)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await set(.volume, toPercent: percent)
        return .result(dialog: "Display volume set to \(percent)%.")
    }
}

enum MuteAction: String, AppEnum {
    case mute, unmute, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mute Action"
    static let caseDisplayRepresentations: [MuteAction: DisplayRepresentation] = [
        .mute: "Mute", .unmute: "Unmute", .toggle: "Toggle Mute",
    ]
}

struct SetMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute Display"
    static let description = IntentDescription("Mutes or unmutes your external display's speakers.")

    @Parameter(title: "Action", default: .toggle)
    var action: MuteAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) display sound")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let displays = try await displays(supporting: .volume)
        let muted = switch action {
        case .mute: true
        case .unmute: false
        case .toggle: !displays[0].isMuted
        }
        for display in displays { display.setMuted(muted) }
        HUD.shared.show(.volume, for: displays[0])
        return .result(dialog: muted ? "Display muted." : "Display unmuted.")
    }
}

struct GetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Display Brightness"
    static let description = IntentDescription("Returns your external display's brightness, from 0 to 100.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let value = try await percent(of: .brightness)
        return .result(value: value, dialog: "Display brightness is \(value)%.")
    }
}

struct GetVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Display Volume"
    static let description = IntentDescription("Returns your external display's speaker volume, from 0 to 100.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let value = try await percent(of: .volume)
        return .result(value: value, dialog: "Display volume is \(value)%.")
    }
}

struct DisplayShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: ["Set brightness with \(.applicationName)", "Set display brightness with \(.applicationName)"],
            shortTitle: "Set Brightness",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: SetVolumeIntent(),
            phrases: ["Set volume with \(.applicationName)", "Set display volume with \(.applicationName)"],
            shortTitle: "Set Volume",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: SetMuteIntent(),
            phrases: ["\(\.$action) sound with \(.applicationName)", "Mute display with \(.applicationName)"],
            shortTitle: "Mute Display",
            systemImageName: "speaker.slash.fill"
        )
        AppShortcut(
            intent: GetBrightnessIntent(),
            phrases: ["Get brightness with \(.applicationName)", "What's my display brightness in \(.applicationName)"],
            shortTitle: "Get Brightness",
            systemImageName: "sun.min"
        )
    }
}
