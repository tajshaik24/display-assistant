import SwiftUI

extension DisplayModel.Control {
    var title: String {
        switch self {
        case .brightness: "Brightness"
        case .volume: "Volume"
        }
    }

    /// Module heading, named as in Control Center.
    var moduleTitle: String {
        switch self {
        case .brightness: "Display"
        case .volume: "Sound"
        }
    }

    var minimumSymbol: String {
        switch self {
        case .brightness: "sun.min.fill"
        case .volume: "speaker.fill"
        }
    }

    var maximumSymbol: String {
        switch self {
        case .brightness: "sun.max.fill"
        case .volume: "speaker.wave.3.fill"
        }
    }

    /// Single symbol summarizing the current level, for the on-screen indicator.
    func symbol(value: Double, muted: Bool = false) -> String {
        switch self {
        case .brightness: value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value == 0 { "speaker.slash.fill" }
            else if value < 0.34 { "speaker.wave.1.fill" }
            else if value < 0.67 { "speaker.wave.2.fill" }
            else { "speaker.wave.3.fill" }
        }
    }
}

/// A Control Center style module: heading, then a thin neutral track between a small and a large icon.
struct ControlSlider: View {
    let control: DisplayModel.Control
    let value: Double
    /// Muted: like macOS, the track shows empty while the underlying value is kept.
    var isMuted = false
    let onChange: (Double) -> Void
    var onMinimumIconTap: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    private static let trackHeight: CGFloat = 6
    private static let hitHeight: CGFloat = 22
    private static let knobSize: CGFloat = 16

    private var shownValue: Double { isMuted ? 0 : value }
    private var valueText: String { isMuted ? "Muted" : "\(Int((value * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(control.moduleTitle).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : control.minimumSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: Self.hitHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onMinimumIconTap?() }
                    .allowsHitTesting(onMinimumIconTap != nil)
                track
                Image(systemName: control.maximumSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: Self.hitHeight)
            }
            .foregroundStyle(.primary.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement()
        .accessibilityLabel(control.title)
        .accessibilityValue(isMuted ? "Muted" : "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            onChange(value + (direction == .increment ? KeyStep.normal : -KeyStep.normal))
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // The knob travels inside the track, so the fill ends exactly where the value is.
            let knobX = Self.knobSize / 2 + (width - Self.knobSize) * shownValue
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.14))
                    .frame(height: Self.trackHeight)
                Capsule().fill(.primary.opacity(0.9))
                    .frame(width: shownValue == 0 ? 0 : knobX, height: Self.trackHeight)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .offset(x: knobX - Self.knobSize / 2)
                    .opacity(isDragging || isHovering ? 1 : 0)
            }
            .frame(height: Self.hitHeight)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChange((drag.location.x - Self.knobSize / 2) / (width - Self.knobSize))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.snappy(duration: 0.15), value: isDragging || isHovering)
            .animation(.snappy(duration: 0.2), value: isMuted)
        }
        .frame(height: Self.hitHeight)
    }
}
