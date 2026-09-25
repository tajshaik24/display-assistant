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
}

/// The inside of a Control Center style module: a heading, then a thin neutral track between a small
/// and a large icon, and optionally extra controls below. Whoever places it gives it its background.
struct ControlSlider<Accessory: View>: View {
    let control: DisplayModel.Control
    let value: Double
    /// Muted: like macOS, the track shows empty while the underlying value is kept.
    var isMuted = false
    /// Nil for a read-only module, like the on-screen indicator's.
    var onChange: ((Double) -> Void)?
    var onMinimumIconTap: (() -> Void)?
    var showsValue = true
    @ViewBuilder var accessory: Accessory

    @State private var isDragging = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private static var trackHeight: CGFloat { 6 }
    private static var hitHeight: CGFloat { 22 }
    private static var knobSize: CGFloat { 16 }

    private var shownValue: Double { isMuted ? 0 : value }
    private var valueText: String { isMuted ? "Muted" : "\(Int((value * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(control.moduleTitle).font(.system(size: 12, weight: .semibold))
                Spacer()
                if showsValue {
                    Text(valueText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : control.minimumSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16, height: Self.hitHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onMinimumIconTap?() }
                    .allowsHitTesting(onMinimumIconTap != nil)
                track
                Image(systemName: control.maximumSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22, height: Self.hitHeight)
            }
            .foregroundStyle(.primary.opacity(0.72))
            .accessibilityElement()
            .accessibilityLabel(control.title)
            .accessibilityValue(isMuted ? "Muted" : "\(Int((value * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                onChange?(value + (direction == .increment ? KeyStep.normal : -KeyStep.normal))
            }
            accessory
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // The knob travels inside the track, so the fill ends exactly where the value is.
            let knobX = Self.knobSize / 2 + (width - Self.knobSize) * shownValue
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.13))
                    .frame(height: Self.trackHeight)
                // An explicit color: semantic styles are rendered vibrant (and much dimmer) inside glass.
                Capsule().fill(colorScheme == .dark ? Color.white : Color.black.opacity(0.78))
                    .frame(width: shownValue == 0 ? 0 : knobX, height: Self.trackHeight)
                if onChange != nil {
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: Self.knobSize, height: Self.knobSize)
                        .offset(x: knobX - Self.knobSize / 2)
                        .opacity(isDragging || isHovering ? 1 : 0)
                }
            }
            .frame(height: Self.hitHeight)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChange?((drag.location.x - Self.knobSize / 2) / (width - Self.knobSize))
                    }
                    .onEnded { _ in isDragging = false },
                isEnabled: onChange != nil
            )
            .animation(.snappy(duration: 0.15), value: isDragging || isHovering)
            .animation(.snappy(duration: 0.2), value: isMuted)
            .animation(.snappy(duration: 0.18), value: shownValue)
        }
        .frame(height: Self.hitHeight)
    }
}

extension ControlSlider where Accessory == EmptyView {
    init(
        control: DisplayModel.Control,
        value: Double,
        isMuted: Bool = false,
        onChange: ((Double) -> Void)? = nil,
        onMinimumIconTap: (() -> Void)? = nil,
        showsValue: Bool = true
    ) {
        self.init(
            control: control, value: value, isMuted: isMuted, onChange: onChange,
            onMinimumIconTap: onMinimumIconTap, showsValue: showsValue, accessory: { EmptyView() }
        )
    }
}

/// A round button with a label, like Control Center's Dark Mode and Night Shift: filled with the
/// accent color while on.
struct CircleToggle<Glyph: View>: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder var glyph: Glyph

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                glyph
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 28, height: 28)
                    .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.1)), in: .circle)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(isOn ? "On" : "Off").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}
