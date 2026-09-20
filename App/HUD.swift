import AppKit
import SwiftUI

/// The on-screen indicator shown for keyboard and Control Center changes,
/// placed under the menu bar like the system's own.
@MainActor
final class HUD {
    static let shared = HUD()

    private let state = HUDState()
    private var hideTask: Task<Void, Never>?

    private static let size = CGSize(width: 290, height: 52)
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

private struct HUDContent: View {
    @ObservedObject var display: DisplayModel
    let control: DisplayModel.Control
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let value = control == .volume && display.isMuted ? 0 : display.value(control)
        HStack(spacing: 12) {
            Image(systemName: control.symbol(value: value, muted: display.isMuted))
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            GeometryReader { proxy in
                Capsule().fill(.primary.opacity(0.18))
                    .overlay(alignment: .leading) {
                        // An explicit color: semantic styles are rendered vibrant (and much dimmer) inside glass.
                        Capsule().fill(colorScheme == .dark ? Color.white : Color.black.opacity(0.8))
                            .frame(width: value == 0 ? 0 : max(6, proxy.size.width * value))
                    }
                    .clipShape(Capsule())
            }
            .frame(height: 6)
            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
        .padding(4)
        .animation(.snappy(duration: 0.18), value: value)
    }
}
