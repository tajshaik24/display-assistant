import AppKit
import Combine
import Sparkle

/// Software updates through Sparkle and its standard windows. Sparkle checks the appcast attached
/// to the latest GitHub release once a day (see SUFeedURL in project.yml).
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        // A menu bar app isn't frontmost, so bring it forward or Sparkle's window opens behind others.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Lets Sparkle show updates found in the background from a menu bar app (which has no Dock icon
    /// to draw attention with). Sparkle still shows its own window for them.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
