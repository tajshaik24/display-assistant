import AppIntents
import SwiftUI
import WidgetKit

@main
struct DisplayControlsBundle: WidgetBundle {
    var body: some Widget {
        MuteControl()
        BrightnessUpControl()
        BrightnessDownControl()
        VolumeUpControl()
        VolumeDownControl()
    }
}

// MARK: - Mute toggle

struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Shared.muteControlKind, provider: MuteValueProvider()) { isMuted in
            ControlWidgetToggle("Display Sound", isOn: isMuted, action: SetDisplayMuteIntent()) { isOn in
                Label(isOn ? "Muted" : "On", systemImage: isOn ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .tint(.red)
        }
        .displayName("Mute Display")
        .description("Mute or unmute your external display's speakers.")
    }
}

struct MuteValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        Shared.defaults.bool(forKey: Shared.mutedKey)
    }
}

struct SetDisplayMuteIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mute External Display"

    @Parameter(title: "Muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Record the new state up front so the toggle doesn't flicker back before the app confirms it.
        Shared.defaults.set(value, forKey: Shared.mutedKey)
        (value ? DisplayCommand.mute : .unmute).post()
        return .result()
    }
}

// MARK: - Step buttons

struct BrightnessUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tajshaik.DisplayAssistant.control.brightnessUp") {
            ControlWidgetButton(action: BrightnessUpIntent()) {
                Label("Brightness Up", systemImage: "sun.max.fill")
            }
        }
        .displayName("Display Brightness Up")
        .description("Make your external display brighter.")
    }
}

struct BrightnessDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tajshaik.DisplayAssistant.control.brightnessDown") {
            ControlWidgetButton(action: BrightnessDownIntent()) {
                Label("Brightness Down", systemImage: "sun.min.fill")
            }
        }
        .displayName("Display Brightness Down")
        .description("Make your external display dimmer.")
    }
}

struct VolumeUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tajshaik.DisplayAssistant.control.volumeUp") {
            ControlWidgetButton(action: VolumeUpIntent()) {
                Label("Volume Up", systemImage: "speaker.plus.fill")
            }
        }
        .displayName("Display Volume Up")
        .description("Turn your external display's speakers up.")
    }
}

struct VolumeDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tajshaik.DisplayAssistant.control.volumeDown") {
            ControlWidgetButton(action: VolumeDownIntent()) {
                Label("Volume Down", systemImage: "speaker.minus.fill")
            }
        }
        .displayName("Display Volume Down")
        .description("Turn your external display's speakers down.")
    }
}

struct BrightnessUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Increase External Display Brightness"

    func perform() async throws -> some IntentResult {
        DisplayCommand.brightnessUp.post()
        return .result()
    }
}

struct BrightnessDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Decrease External Display Brightness"

    func perform() async throws -> some IntentResult {
        DisplayCommand.brightnessDown.post()
        return .result()
    }
}

struct VolumeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Increase External Display Volume"

    func perform() async throws -> some IntentResult {
        DisplayCommand.volumeUp.post()
        return .result()
    }
}

struct VolumeDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Decrease External Display Volume"

    func perform() async throws -> some IntentResult {
        DisplayCommand.volumeDown.post()
        return .result()
    }
}
