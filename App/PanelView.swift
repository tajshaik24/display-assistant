import SwiftUI

struct PanelView: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject var keyboard: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.displays.isEmpty, store.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            } else if store.displays.isEmpty {
                EmptyStateView()
            } else {
                ForEach(store.displays) { DisplayCard(display: $0) }
            }
            if store.canSync {
                SyncToggle(isOn: $store.isSyncEnabled)
            }
            if !keyboard.isActive {
                KeyboardAccessBanner { keyboard.requestAccess() }
            }
            FooterView()
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct DisplayCard: View {
    @ObservedObject var display: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(Self.displaySettingsURL)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Display Settings")
                .accessibilityLabel("Open Display Settings")
            }
            .padding(.horizontal, 6)

            ForEach(DisplayModel.Control.allCases.filter(display.supports), id: \.self) { control in
                ControlSlider(
                    control: control,
                    value: display.value(control),
                    isMuted: control == .volume && display.isMuted,
                    onChange: { display.set(control, to: $0) },
                    onMinimumIconTap: control == .volume ? { display.setMuted(!display.isMuted) } : nil
                )
            }
        }
    }

    private static let displaySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!

    private var subtitle: String {
        guard let screen = display.screen else { return "External Display" }
        let size = screen.frame.size
        let hertz = screen.maximumFramesPerSecond
        return "\(Int(size.width)) × \(Int(size.height)) · \(hertz) Hz"
    }
}

private struct SyncToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sync Brightness").font(.system(size: 13, weight: .semibold))
                    Text("Displays move together and reach 0% and 100% at the same time")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
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
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}

private struct FooterView: View {
    @State private var launchesAtLogin = LoginItem.isEnabled

    var body: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchesAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
                .onChange(of: launchesAtLogin) { _, enabled in
                    do { try LoginItem.setEnabled(enabled) } catch { launchesAtLogin = LoginItem.isEnabled }
                }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}
