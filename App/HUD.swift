import AppKit
import SwiftUI

/// The on-screen indicator shown for keyboard and Control Center changes, in the same place as the
/// system's own.
@MainActor
final class HUD {
    static let shared = HUD()

    private let state = HUDState()
    private var hideTask: Task<Void, Never>?

    // The system indicator's place, measured on screen: a 308 × 66 pill whose right edge is 17.5 points
    // from the screen's and whose top is 10 points under the menu bar. The panel adds 4 on every side.
    private static let size = CGSize(width: 316, height: 74)
    private static let rightInset: CGFloat = 13.5
    private static let topInset: CGFloat = 6

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

        if let screen = display.screen ?? NSScreen.main {
            panel.setFrameOrigin(CGPoint(
                x: screen.frame.maxX - Self.size.width - Self.rightInset,
                y: screen.visibleFrame.maxY - Self.size.height - Self.topInset
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

/// A read-only pill of icon and segmented track, like the system's own indicator.
private struct HUDContent: View {
    @ObservedObject var display: DisplayModel
    let control: DisplayModel.Control

    var body: some View {
        ControlSlider(
            control: control,
            value: display.value(control),
            isMuted: control == .volume && display.isMuted,
            style: .indicator
        )
        // The system's layout: icon 20.5 points in, track from 62.5 to 31.5 points short of the end.
        .padding(.leading, 20.5)
        .padding(.trailing, 31.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.clear, in: .capsule)
        .padding(4)
    }
}
