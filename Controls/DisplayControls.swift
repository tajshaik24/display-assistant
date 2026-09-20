import AppIntents
import SwiftUI
import WidgetKit

// Control Center only offers buttons and toggles to apps — no sliders. So there is a button
// that opens the app's slider panel, level buttons the user configures, and a mute toggle.

@main
struct DisplayControlsBundle: WidgetBundle {
    var body: some Widget {
        ShowSlidersControl()
        BrightnessLevelControl()
        VolumeLevelControl()
        MuteControl()
    }
}

// MARK: - Open the slider panel

struct ShowSlidersControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tajshaik.DisplayAssistant.control.showSliders") {
            ControlWidgetButton(action: ShowSlidersIntent()) {
                Label("Display Sliders", systemImage: "slider.horizontal.3")
            }
        }
        .displayName("Display Sliders")
        .description("Open the brightness and volume sliders for your external display.")
    }
}

struct ShowSlidersIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Display Sliders"

    func perform() async throws -> some IntentResult {
        DisplayCommand.showPanel.post()
        return .result()
    }
}

// MARK: - Configurable levels

struct BrightnessLevelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "com.tajshaik.DisplayAssistant.control.brightnessLevel",
            intent: BrightnessLevelConfiguration.self
        ) { configuration in
            ControlWidgetButton(action: ApplyBrightnessLevelIntent(percent: configuration.percent)) {
                Label("Brightness \(configuration.percent)%", systemImage: configuration.percent < 50 ? "sun.min.fill" : "sun.max.fill")
            }
        }
        .displayName("Display Brightness Level")
        .description("Set your external display to a brightness you choose. Add one for each level you use.")
        .promptsForUserConfiguration()
    }
}

struct BrightnessLevelConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Brightness Level"

    @Parameter(title: "Brightness (%)", default: 50, inclusiveRange: (0, 100))
    var percent: Int
}

struct ApplyBrightnessLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Display Brightness Level"
    static let isDiscoverable = false

    @Parameter(title: "Brightness (%)")
    var percent: Int

    init() {}

    init(percent: Int) {
        self.percent = percent
    }

    func perform() async throws -> some IntentResult {
        DisplayCommand.setBrightness(percent: percent).post()
        return .result()
    }
}

struct VolumeLevelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "com.tajshaik.DisplayAssistant.control.volumeLevel",
            intent: VolumeLevelConfiguration.self
        ) { configuration in
            ControlWidgetButton(action: ApplyVolumeLevelIntent(percent: configuration.percent)) {
                Label("Volume \(configuration.percent)%", systemImage: configuration.percent < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
            }
        }
        .displayName("Display Volume Level")
        .description("Set your external display's speakers to a volume you choose. Add one for each level you use.")
        .promptsForUserConfiguration()
    }
}

struct VolumeLevelConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Volume Level"

    @Parameter(title: "Volume (%)", default: 25, inclusiveRange: (0, 100))
    var percent: Int
}

struct ApplyVolumeLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Display Volume Level"
    static let isDiscoverable = false

    @Parameter(title: "Volume (%)")
    var percent: Int

    init() {}

    init(percent: Int) {
        self.percent = percent
    }

    func perform() async throws -> some IntentResult {
        DisplayCommand.setVolume(percent: percent).post()
        return .result()
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
