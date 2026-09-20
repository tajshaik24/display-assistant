import SwiftUI

@main
struct DisplayAssistantApp: App {
    @StateObject private var services = Services()

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
private final class Services: ObservableObject {
    let store: DisplayStore
    let keyboard: KeyboardController

    init() {
        store = .shared
        keyboard = KeyboardController(store: store)
        LoginItem.enableOnFirstLaunch()
    }
}
