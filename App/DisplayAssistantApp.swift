import SwiftUI

@main
struct DisplayAssistantApp: App {
    private let services = Services.shared

    /// MenuBarExtra ignores font and frame modifiers on its label, so the symbol is sized up front.
    private static let menuBarIcon: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15.3, weight: .medium)
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display Assistant")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: services.store, keyboard: services.keyboard)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the long-lived objects; created at launch so the keyboard keys and
/// Control Center work without the panel ever being opened.
@MainActor
final class Services {
    static let shared = Services()

    let store: DisplayStore
    let keyboard: KeyboardController

    private init() {
        store = .shared
        keyboard = KeyboardController(store: store)
        LoginItem.enableOnFirstLaunch()
    }
}
