import CoreGraphics
import Foundation

/// The per-display HDR switch from System Settings › Displays, through the private SkyLight framework.
///
/// Like ``NativeBrightness``, the symbols are looked up at run time, so a macOS release that
/// drops them only hides the switch.
public enum HDRMode {
    private typealias Query = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Set = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    private static let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let supportsHDR: Query? = symbol("SLSDisplaySupportsHDRMode")
    private static let isHDREnabled: Query? = symbol("SLSDisplayIsHDRModeEnabled")
    private static let setHDREnabled: Set? = symbol("SLSDisplaySetHDRModeEnabled")

    public static func isSupported(_ display: CGDirectDisplayID) -> Bool {
        isHDREnabled != nil && setHDREnabled != nil && supportsHDR?(display) == true
    }

    public static func isEnabled(_ display: CGDirectDisplayID) -> Bool {
        isHDREnabled?(display) == true
    }

    /// Switching reconfigures the display, so the screen blanks for a moment.
    @discardableResult
    public static func setEnabled(_ display: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        setHDREnabled?(display, enabled) == 0
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
