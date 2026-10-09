// Renders the app icon into App/Assets.xcassets. Run with: swift scripts/make-icon.swift
// Set ICON_PREVIEW=/path/to/file.png to write only a 1024px preview instead.
//
// The design: a sun drawn as a dial on graphite. Twelve marks brighten clockwise, like a knob
// turned up from seven o'clock, around a softly lit disc. No colour.
import AppKit

let canvas = 1024
let canvasRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let center = CGPoint(x: 512, y: 512)

// The standard macOS icon body, 824pt centered on the 1024pt canvas.
let body = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: white, green: white, blue: white + 0.01, alpha: alpha)
}

func circle(_ radius: CGFloat, at point: CGPoint = center) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}

func render(pixels: Int = canvas, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = canvasRect.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

/// Fills the outline of `path` with a vertical white gradient, for a lit edge.
func strokeRim(_ path: NSBezierPath, width: CGFloat, top: CGFloat, bottom: CGFloat, in context: CGContext) {
    context.saveGState()
    context.addPath(path.cgPath)
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    NSGradient(colors: [gray(1, top), gray(1, bottom)])!.draw(in: path.bounds.insetBy(dx: -width, dy: -width), angle: -90)
    context.restoreGState()
}

let master = render { context in
    // Body: graphite.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: gray(0, 0.3).cgColor)
    gray(0.5).setFill()
    body.fill()
    context.restoreGState()
    NSGradient(colors: [gray(0.27), gray(0.15), gray(0.09)])!.draw(in: body, angle: -90)
    strokeRim(body, width: 4, top: 0.25, bottom: 0.04, in: context)

    // The marks, dimmest at seven o'clock and brightest at six.
    for index in 0..<12 {
        let angle = (240 - CGFloat(index) * 30) * .pi / 180
        let point = CGPoint(x: center.x + cos(angle) * 250, y: center.y + sin(angle) * 250)
        gray(1, 0.18 + 0.78 * CGFloat(index) / 11).setFill()
        circle(26, at: point).fill()
    }

    // The disc, softly lit.
    context.saveGState()
    context.setShadow(offset: .zero, blur: 60, color: gray(1, 0.3).cgColor)
    gray(0.97).setFill()
    circle(150).fill()
    context.restoreGState()
}

if let preview = ProcessInfo.processInfo.environment["ICON_PREVIEW"] {
    try master.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
    print("Wrote preview to \(preview)")
    exit(0)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        let scaled = render(pixels: points * scale) { context in
            context.interpolationQuality = .high
            context.draw(master.cgImage!, in: canvasRect)
        }
        try scaled.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let info = ["author": "xcode", "version": 1] as [String: Any]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconset.path)")
