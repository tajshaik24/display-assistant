import CoreGraphics
import Foundation

/// Brightness of displays macOS controls itself (built-in panels, Studio Display, LG UltraFine, ...),
/// through the private DisplayServices framework.
///
/// The symbols are looked up at run time rather than linked, so a macOS release that
/// drops them only costs this feature instead of stopping the app from launching.
public enum NativeBrightness {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let canChangeBrightness: CanChange? = symbol("DisplayServicesCanChangeBrightness")
    private static let getBrightness: Get? = symbol("DisplayServicesGetBrightness")
    private static let setBrightness: Set? = symbol("DisplayServicesSetBrightness")

    public static var isAvailable: Bool {
        canChangeBrightness != nil && getBrightness != nil && setBrightness != nil
    }

    public static func canChange(_ display: CGDirectDisplayID) -> Bool {
        isAvailable && canChangeBrightness?(display) == true
    }

    /// Brightness from 0 to 1, or nil when the display doesn't report one.
    public static func get(_ display: CGDirectDisplayID) -> Double? {
        var brightness: Float = 0
        guard let getBrightness, getBrightness(display, &brightness) == 0 else { return nil }
        return Double(brightness)
    }

    @discardableResult
    public static func set(_ display: CGDirectDisplayID, to brightness: Double) -> Bool {
        setBrightness?(display, Float(min(1, max(0, brightness)))) == 0
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
