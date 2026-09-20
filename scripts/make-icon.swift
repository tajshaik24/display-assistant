// Renders the app icon into App/Assets.xcassets. Run with: swift scripts/make-icon.swift
//
// The design: a sun rising behind the corner of a frosted-glass display. The glass is real —
// whatever is behind the pane is blurred and drawn back into it.
import AppKit
import CoreImage

let canvas = 1024
let canvasRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)

// The standard macOS icon body, 824pt centered on the 1024pt canvas.
let body = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
let pane = CGRect(x: 212, y: 380, width: 600, height: 380)
let panePath = NSBezierPath(roundedRect: pane, xRadius: 54, yRadius: 54)
let sunCenter = CGPoint(x: pane.maxX - 72, y: pane.maxY - 52)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
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

/// Fills the outline of `path` with a vertical white gradient, for a lit glass edge.
func strokeRim(_ path: NSBezierPath, width: CGFloat, top: CGFloat, bottom: CGFloat, in context: CGContext) {
    context.saveGState()
    context.addPath(path.cgPath)
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    NSGradient(colors: [color(1, 1, 1, top), color(1, 1, 1, bottom)])!.draw(in: path.bounds.insetBy(dx: -width, dy: -width), angle: -90)
    context.restoreGState()
}

// 1. Everything that sits behind the glass: background and sun.
let backdrop = render { context in
    body.addClip()
    NSGradient(colors: [color(0.20, 0.13, 0.52), color(0.10, 0.22, 0.72), color(0.04, 0.42, 0.90)])!
        .draw(in: body.bounds, angle: -55)
    // Screen-blended so the glow lifts the blue toward warm light instead of mixing into grey.
    context.saveGState()
    context.setBlendMode(.screen)
    NSGradient(colors: [color(1.0, 0.55, 0.25, 0.85), color(0.9, 0.3, 0.45, 0.35), color(0.6, 0.2, 0.6, 0)])!
        .draw(fromCenter: sunCenter, radius: 60, toCenter: sunCenter, radius: 400, options: [])
    context.restoreGState()
    let sun = NSBezierPath(ovalIn: CGRect(x: sunCenter.x - 122, y: sunCenter.y - 122, width: 244, height: 244))
    NSGradient(colors: [color(1.0, 0.93, 0.55), color(1.0, 0.72, 0.22), color(1.0, 0.5, 0.16)])!
        .draw(in: sun, relativeCenterPosition: CGPoint(x: -0.25, y: 0.3))
}

// 2. The same scene, frosted.
let ciContext = CIContext()
let blurred = CIImage(bitmapImageRep: backdrop)!
    .clampedToExtent()
    .applyingGaussianBlur(sigma: 34)
    .cropped(to: canvasRect)
let frosted = ciContext.createCGImage(blurred, from: canvasRect)!

// 3. Composite.
let master = render { context in
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.32).cgColor)
    color(0.1, 0.15, 0.5).setFill()
    body.fill()
    context.restoreGState()
    context.draw(backdrop.cgImage!, in: canvasRect)

    // Stand, in the same glass.
    color(1, 1, 1, 0.3).setFill()
    NSBezierPath(rect: CGRect(x: 476, y: 312, width: 72, height: 68)).fill()
    let base = NSBezierPath(roundedRect: CGRect(x: 392, y: 280, width: 240, height: 36), xRadius: 18, yRadius: 18)
    color(1, 1, 1, 0.5).setFill()
    base.fill()
    strokeRim(base, width: 4, top: 0.7, bottom: 0.1, in: context)

    // The pane: a soft shadow, the frosted scene, a light tint, a sheen and a lit rim.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0, 0, 0.15, 0.4).cgColor)
    color(0, 0, 0.2, 0.5).setFill()
    panePath.fill()
    context.restoreGState()

    context.saveGState()
    panePath.addClip()
    context.draw(frosted, in: canvasRect)
    NSGradient(colors: [color(1, 1, 1, 0.26), color(1, 1, 1, 0.07)])!.draw(in: pane, angle: -90)
    NSGradient(colors: [color(1, 1, 1, 0.2), color(1, 1, 1, 0)])!
        .draw(in: CGRect(x: pane.minX, y: pane.midY + 40, width: pane.width, height: pane.height / 2 - 40), angle: -90)
    context.restoreGState()
    strokeRim(panePath, width: 6, top: 0.85, bottom: 0.12, in: context)
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
