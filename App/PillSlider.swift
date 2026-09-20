import SwiftUI

extension DisplayModel.Control {
    var title: String {
        switch self {
        case .brightness: "Brightness"
        case .volume: "Volume"
        }
    }

    var tint: LinearGradient {
        let colors: [Color] = switch self {
        case .brightness: [Color(red: 1.0, green: 0.78, blue: 0.25), Color(red: 1.0, green: 0.58, blue: 0.2)]
        case .volume: [Color(red: 0.35, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.45, blue: 1.0)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

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

/// A thick Control Center style slider with its icon and value inside the track.
struct PillSlider: View {
    let control: DisplayModel.Control
    let value: Double
    /// Muted: like macOS, the bar shows empty while the underlying value is kept.
    var isMuted = false
    let onChange: (Double) -> Void
    var onIconTap: (() -> Void)?

    @State private var isDragging = false

    private var valueText: String { isMuted ? "Muted" : "\(Int((value * 100).rounded()))%" }

    private static let height: CGFloat = 34
    private static let iconInset: CGFloat = 40

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                control.tint
                    // Keep the fill wide enough to sit behind the icon so it never looks detached.
                    .frame(width: isMuted ? 0 : Self.iconInset + (width - Self.iconInset) * value)
                HStack {
                    Image(systemName: control.symbol(value: value, muted: isMuted))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                        .shadow(color: .black.opacity(isMuted ? 0 : 0.25), radius: 1, y: 0.5)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Self.iconInset, height: Self.height)
                        .contentShape(Rectangle())
                        .onTapGesture { onIconTap?() }
                        .allowsHitTesting(onIconTap != nil)
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        isDragging = true
                        onChange((drag.location.x - Self.iconInset) / (width - Self.iconInset))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .scaleEffect(y: isDragging ? 1.06 : 1)
            .animation(.snappy(duration: 0.2), value: isDragging)
            .animation(.snappy(duration: 0.2), value: isMuted)
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(control.title)
        .accessibilityValue(isMuted ? "Muted" : "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            onChange(value + (direction == .increment ? KeyStep.normal : -KeyStep.normal))
        }
    }
}
