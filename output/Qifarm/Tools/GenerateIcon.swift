import AppKit

// Vector-drawn footsteps on teal, rendered as an opaque iOS app icon.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.02, green: 0.37, blue: 0.39, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
func footprint(x: CGFloat, y: CGFloat, angle: CGFloat, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: x, byY: y)
    var rotation = AffineTransform(rotationByDegrees: angle)
    rotation.append(transform)
    (rotation as NSAffineTransform).concat()
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: -85, y: -90, width: 170, height: 260), xRadius: 80, yRadius: 80).fill()
    NSBezierPath(ovalIn: NSRect(x: -64, y: -225, width: 128, height: 105)).fill()
    NSGraphicsContext.restoreGraphicsState()
}
footprint(x: 365, y: 440, angle: 22, color: .white)
footprint(x: 650, y: 645, angle: -18,
          color: NSColor(calibratedRed: 0.63, green: 0.94, blue: 0.72, alpha: 1))
NSGraphicsContext.current?.cgContext.flush()
NSGraphicsContext.restoreGraphicsState()
let target = CommandLine.arguments[1]
// JPEG encoding flattens the fully painted bitmap into opaque RGB for App Store icons.
let opaque = NSBitmapImageRep(data: bitmap.representation(using: .jpeg,
    properties: [.compressionFactor: 1.0])!)!
try opaque.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: target))
