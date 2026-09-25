import AppKit
import SwiftUI

/// The on-screen indicator shown for keyboard and Control Center changes,
/// placed under the menu bar like the system's own.
@MainActor
final class HUD {
    static let shared = HUD()

    private let state = HUDState()
    private var hideTask: Task<Void, Never>?

    private static let size = CGSize(width: 262, height: 78)
    private static let margin: CGFloat = 10

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        return panel
    }()

    func show(_ control: DisplayModel.Control, for display: DisplayModel) {
        state.control = control
        state.display = display

        let screen = display.screen ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(
                x: frame.maxX - Self.size.width - Self.margin,
                y: frame.maxY - Self.size.height - Self.margin
            ))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.panel.alphaValue == 0 else { return }
                    self.panel.orderOut(nil)
                }
            }
        }
    }
}

@MainActor
private final class HUDState: ObservableObject {
    @Published var control: DisplayModel.Control = .brightness
    @Published var display: DisplayModel?
}

private struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        if let display = state.display {
            HUDContent(display: display, control: state.control)
        }
    }
}

/// A small read-only Control Center module, like the system's own indicator.
private struct HUDContent: View {
    @ObservedObject var display: DisplayModel
    let control: DisplayModel.Control

    var body: some View {
        ControlSlider(
            control: control,
            value: display.value(control),
            isMuted: control == .volume && display.isMuted,
            showsValue: false
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(4)
    }
}
