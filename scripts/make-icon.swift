import AppKit
import Foundation

// Original vector artwork: a rising power-switch sun. Each size is drawn from
// geometry, with optical adjustments at 16/32 px instead of downscaling a bitmap.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, pixels) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    NSGraphicsContext.current?.imageInterpolation = .high
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowOffset = NSSize(width: 0, height: -11)
    shadow.shadowBlurRadius = 23
    shadow.set()
    NSColor(srgbRed: 0.96, green: 0.61, blue: 0.12, alpha: 1).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.65, blue: 0.18, alpha: 1),
        ending: NSColor(srgbRed: 1, green: 0.91, blue: 0.59, alpha: 1))!.draw(in: background, angle: 90)
    NSColor.white.withAlphaComponent(0.33).setStroke()
    background.lineWidth = 3
    background.stroke()

    // Clip at the horizon: the power circle itself is the rising sun.
    // Its lower arc stays below the horizon instead of floating above a line.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: 340, width: 1024, height: 684)).addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: 237, y: 205, width: 550, height: 550))
    NSColor.white.withAlphaComponent(0.19).setFill()
    glow.fill()
    let ink = NSColor(srgbRed: 0.24, green: 0.17, blue: 0.11, alpha: 1)
    ink.setStroke()
    let isSmall = pixels <= 32
    let center = NSPoint(x: 512, y: 480)
    // Three rays preserve the sunrise silhouette even at menu-size resolution.
    for degrees in [30.0, 90.0, 150.0] {
        let angle = degrees * .pi / 180
        let ray = NSBezierPath()
        ray.move(to: NSPoint(x: center.x + cos(angle) * 294, y: center.y + sin(angle) * 294))
        ray.line(to: NSPoint(x: center.x + cos(angle) * 338, y: center.y + sin(angle) * 338))
        ray.lineWidth = isSmall ? 39 : 30
        ray.lineCapStyle = .round
        ray.stroke()
    }
    let power = NSBezierPath()
    power.appendArc(withCenter: center, radius: 210, startAngle: 130, endAngle: 410, clockwise: false)
    power.lineWidth = isSmall ? 65 : 57
    power.lineCapStyle = .round
    power.stroke()
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 512, y: 710))
    stem.line(to: NSPoint(x: 512, y: 500))
    stem.lineWidth = isSmall ? 65 : 57
    stem.lineCapStyle = .round
    stem.stroke()
    NSGraphicsContext.restoreGraphicsState()
    ink.setStroke()
    let horizon = NSBezierPath()
    horizon.move(to: NSPoint(x: 226, y: 340))
    horizon.line(to: NSPoint(x: 798, y: 340))
    horizon.lineWidth = isSmall ? 47 : 38
    horizon.lineCapStyle = .round
    horizon.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: destination.appendingPathComponent(name + ".png"))
}
