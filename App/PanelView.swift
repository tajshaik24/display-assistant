import SwiftUI

/// The slider panel, laid out like the system's own menu bar panels (Sound, Wi-Fi): Control Center
/// modules per display, then plain menu items.
struct PanelView: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject var keyboard: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.displays.isEmpty, store.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            } else if store.displays.isEmpty {
                EmptyStateView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.displays) { DisplaySection(display: $0) }
                }
            }
            if store.canSync {
                CircleToggle(title: "Sync Brightness", isOn: store.isSyncEnabled) {
                    store.isSyncEnabled.toggle()
                } glyph: {
                    Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                }
                .help("Displays move together and reach 0% and 100% at the same time")
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            if !keyboard.isActive {
                KeyboardAccessBanner { keyboard.requestAccess() }
                    .padding(.top, 6)
            }
            MenuDivider()
            MenuFooter()
        }
        .padding(6)
        .frame(width: 320)
        .onAppear { store.refreshValues() }
    }
}

private struct DisplaySection: View {
    @ObservedObject var display: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)

            if display.supports(.brightness) {
                ControlSlider(
                    control: .brightness,
                    value: display.value(.brightness),
                    onChange: { display.set(.brightness, to: $0) }
                ) {
                    if display.supportsHDR {
                        CircleToggle(title: "High Dynamic Range", isOn: display.isHDREnabled) {
                            display.setHDR(!display.isHDREnabled)
                        } glyph: {
                            Text("HDR").font(.system(size: 8.5, weight: .heavy))
                        }
                        .padding(.top, 3)
                    }
                }
                .modifier(ModuleBackground())
            }
            if display.supports(.volume) {
                ControlSlider(
                    control: .volume,
                    value: display.value(.volume),
                    isMuted: display.isMuted,
                    onChange: { display.set(.volume, to: $0) },
                    onMinimumIconTap: { display.setMuted(!display.isMuted) }
                )
                .modifier(ModuleBackground())
            }
        }
    }

    /// "5K · 144 Hz", from the display's current mode.
    private var subtitle: String {
        guard let mode = CGDisplayCopyDisplayMode(display.id) else { return "" }
        let resolution = switch (mode.pixelWidth, mode.pixelHeight) {
        case (6016, _): "6K"
        case (5120, _): "5K"
        case (3840, 2160), (4096, 2160): "4K"
        case let (width, height): "\(width) × \(height)"
        }
        let hertz = display.screen?.maximumFramesPerSecond ?? Int(mode.refreshRate.rounded())
        return hertz > 0 ? "\(resolution) · \(hertz) Hz" : resolution
    }
}

/// A module's card inside the panel: a faint fill, since the panel itself is already glass.
private struct ModuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 11)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 5)
    }
}

private struct MenuFooter: View {
    @State private var launchesAtLogin = LoginItem.isEnabled

    private static let displaySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItem(title: "Displays Settings…") {
                NSWorkspace.shared.open(Self.displaySettingsURL)
            }
            MenuItem(title: "Launch at Login") {
                do { try LoginItem.setEnabled(!launchesAtLogin) } catch {}
                launchesAtLogin = LoginItem.isEnabled
            } trailing: {
                if launchesAtLogin {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .accessibilityAddTraits(launchesAtLogin ? .isSelected : [])
            MenuItem(title: "Quit Display Assistant") {
                NSApp.terminate(nil)
            } trailing: {
                Text("⌘Q").foregroundStyle(.secondary)
            }
            .keyboardShortcut("q")
        }
    }
}

/// A row that looks and highlights like a menu item in the system's menu bar panels.
private struct MenuItem<Trailing: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                trailing
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(isHovering ? AnyShapeStyle(.primary.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

extension MenuItem where Trailing == EmptyView {
    init(title: String, action: @escaping () -> Void) {
        self.init(title: title, action: action, trailing: { EmptyView() })
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No controllable displays").font(.system(size: 13, weight: .semibold))
            Text("Connect a display that supports DDC/CI over USB-C, DisplayPort or HDMI.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
    }
}

private struct KeyboardAccessBanner: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Text("Use your keyboard's brightness and volume keys")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Enable", action: action).controlSize(.small)
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}
