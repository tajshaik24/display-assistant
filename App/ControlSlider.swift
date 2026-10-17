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

    /// The leading icon, which follows the level like the system's indicator: the speaker gains a wave
    /// per third, the sun grows its rays past half.
    func symbol(for value: Double, isMuted: Bool) -> String {
        switch self {
        case .brightness: value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume where isMuted: "speaker.slash.fill"
        case .volume:
            switch value {
            case ..<0.01: "speaker.fill"
            case ..<(1.0 / 3): "speaker.wave.1.fill"
            case ..<(2.0 / 3): "speaker.wave.2.fill"
            default: "speaker.wave.3.fill"
            }
        }
    }
}

enum ControlSliderStyle {
    /// A card in the panel: a heading over the icon and the track.
    case module
    /// The on-screen indicator: a larger white icon and a hairline track, nothing else.
    case indicator
}

/// The inside of a Control Center style module: a heading, then an icon beside a segmented track like
/// the system's volume and brightness indicator, and optionally extra controls below. Whoever places it
/// gives it its background.
struct ControlSlider<Accessory: View>: View {
    let control: DisplayModel.Control
    let value: Double
    /// Muted: like macOS, the track shows empty while the underlying value is kept.
    var isMuted = false
    /// Nil for a read-only module, like the on-screen indicator's.
    var onChange: ((Double) -> Void)?
    var onIconTap: (() -> Void)?
    var style = ControlSliderStyle.module
    @ViewBuilder var accessory: Accessory

    private var shownValue: Double { isMuted ? 0 : value }
    private var valueText: String { isMuted ? "Muted" : "\(Int((value * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if style == .module {
                HStack(alignment: .firstTextBaseline) {
                    Text(control.moduleTitle).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: style == .module ? 12 : 14) {
                Image(systemName: control.symbol(for: value, isMuted: isMuted))
                    .font(.system(size: style == .module ? 15 : 22, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: style == .module ? 22 : 28, height: SegmentedTrack.hitHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onIconTap?() }
                    .allowsHitTesting(onIconTap != nil)
                SegmentedTrack(value: shownValue, style: style, onChange: onChange)
                    .animation(.snappy(duration: 0.2), value: isMuted)
            }
            .foregroundStyle(style == .module ? AnyShapeStyle(.primary.opacity(0.8)) : AnyShapeStyle(.white))
            .accessibilityElement()
            .accessibilityLabel(control.title)
            .accessibilityValue(isMuted ? "Muted" : "\(Int((value * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                onChange?(value + (direction == .increment ? KeyStep.normal : -KeyStep.normal))
            }
            // The icon is merged into this element, so its tap is offered as an action instead.
            .accessibilityActions {
                if let onIconTap {
                    Button(isMuted ? "Unmute" : "Mute", action: onIconTap)
                }
            }
            accessory
        }
    }
}

/// A row of short bars, one per key press, lit from the left. A value between steps lights part of a bar,
/// so fine (⌥⇧) steps still show. Dragging anywhere on it sets the value.
private struct SegmentedTrack: View {
    let value: Double
    let style: ControlSliderStyle
    let onChange: ((Double) -> Void)?

    @State private var isActive = false
    @Environment(\.colorScheme) private var colorScheme

    static let hitHeight: CGFloat = 22
    private static let segments = Int((1 / KeyStep.normal).rounded())

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Thickens under the pointer, as the hint that it can be dragged.
            let height: CGFloat = style == .indicator ? 4 : isActive ? 7 : 5
            ZStack {
                Segments(count: Self.segments, value: 1).fill(unlit)
                Segments(count: Self.segments, value: value).fill(lit)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in if onChange != nil { isActive = hovering } }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard width > 0 else { return }
                        onChange?(min(max(drag.location.x / width, 0), 1))
                    },
                isEnabled: onChange != nil
            )
            .animation(.snappy(duration: 0.15), value: isActive)
            .animation(.snappy(duration: 0.18), value: value)
        }
        .frame(height: Self.hitHeight)
    }

    // Explicit colors: semantic styles are rendered vibrant (and much dimmer) inside glass. The indicator
    // is always white on its glass, like the system's.
    private var lit: Color {
        style == .indicator || colorScheme == .dark ? .white : .black.opacity(0.78)
    }

    private var unlit: Color {
        style == .indicator ? .white.opacity(0.3) : colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.1)
    }
}

/// `count` rounded bars with small gaps between them, filled up to `value`.
private struct Segments: Shape {
    let count: Int
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let gap: CGFloat = 1
        let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let radius = min(rect.height / 2, 1)
        var path = Path()
        for index in 0..<count {
            let lit = min(max(value * Double(count) - Double(index), 0), 1)
            guard lit > 0 else { break }
            let segment = CGRect(
                x: rect.minX + CGFloat(index) * (width + gap), y: rect.minY,
                width: width * lit, height: rect.height
            )
            path.addRoundedRect(in: segment, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

extension ControlSlider where Accessory == EmptyView {
    init(
        control: DisplayModel.Control,
        value: Double,
        isMuted: Bool = false,
        onChange: ((Double) -> Void)? = nil,
        onIconTap: (() -> Void)? = nil,
        style: ControlSliderStyle = .module
    ) {
        self.init(
            control: control, value: value, isMuted: isMuted, onChange: onChange,
            onIconTap: onIconTap, style: style, accessory: { EmptyView() }
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
