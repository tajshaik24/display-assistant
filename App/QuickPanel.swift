import AppKit
import SwiftUI

/// The slider panel as a free-standing window, opened from the Control Center button.
/// It appears where Control Center does and closes as soon as the user clicks elsewhere.
@MainActor
final class QuickPanel: NSObject, NSWindowDelegate {
    static let shared = QuickPanel()

    private static let margin: CGFloat = 10

    private lazy var panel: NSPanel = {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickPanelView())
        return panel
    }()

    func show() {
        guard let contentView = panel.contentView else { return }
        // The hosted view stays alive between showings, so its onAppear won't re-read the displays.
        DisplayStore.shared.refreshValues()
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let size = contentView.fittingSize
        if let frame = screen?.visibleFrame {
            let origin = CGPoint(x: frame.maxX - size.width - Self.margin, y: frame.maxY - size.height - Self.margin)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        }
        // Taking focus is what dismisses Control Center, leaving the panel in its place.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }
}

/// Borderless panels refuse key status by default, which the click-outside dismissal relies on.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private struct QuickPanelView: View {
    var body: some View {
        PanelView(store: Services.shared.store, keyboard: Services.shared.keyboard)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.12)))
    }
}
