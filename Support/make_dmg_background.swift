import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Support/dmg/background.png")
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let size = NSSize(width: 660, height: 420)
let image = NSImage(size: size)
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [color(0.16, 0.17, 0.23), color(0.12, 0.13, 0.18)])!
    .draw(in: bounds, angle: -90)

func glow(_ center: CGPoint, _ radius: CGFloat, _ tint: NSColor) {
    let colors = [tint.cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
}

glow(CGPoint(x: 640, y: 390), 330, color(0.47, 0.36, 0.94, 0.30))
glow(CGPoint(x: 20, y: 30), 280, color(0.82, 0.31, 0.64, 0.12))

let dotColor = color(1, 1, 1, 0.035)
dotColor.setFill()
for x in stride(from: 12.0, through: 648.0, by: 24.0) {
    for y in stride(from: 12.0, through: 408.0, by: 24.0) {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill()
    }
}

for centerX in [180.0, 480.0] {
    let halo = NSBezierPath(ovalIn: NSRect(x: centerX - 84, y: 210 - 84, width: 168, height: 168))
    color(0.47, 0.36, 0.94, 0.055).setFill()
    halo.fill()
    halo.lineWidth = 1
    color(0.73, 0.58, 0.98, 0.16).setStroke()
    halo.stroke()
}

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 274, y: 210))
arrow.line(to: NSPoint(x: 382, y: 210))
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(0.73, 0.58, 0.98, 0.95).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 370, y: 200))
head.line(to: NSPoint(x: 384, y: 210))
head.line(to: NSPoint(x: 370, y: 220))
head.lineWidth = 2.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

func drawCentered(_ text: String, font: NSFont, tint: NSColor, y: CGFloat, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: tint,
        .kern: kern,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let width = string.size().width
    string.draw(at: NSPoint(x: (size.width - width) / 2, y: y))
}

drawCentered(
    "DiskScope",
    font: NSFont.systemFont(ofSize: 26, weight: .semibold),
    tint: color(0.97, 0.97, 0.95),
    y: 352
)
drawCentered(
    "DISK ANALYZER",
    font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
    tint: color(0.74, 0.58, 0.98),
    y: 334,
    kern: 1.6
)
drawCentered(
    "Перетащите DiskScope в Applications",
    font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
    tint: color(0.85, 0.86, 0.92),
    y: 62
)
drawCentered(
    "Universal · macOS 14+",
    font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
    tint: color(0.45, 0.48, 0.62),
    y: 36,
    kern: 0.5
)

image.unlockFocus()

// Finder backgrounds are sized in points. Render at 1x so the 660×420 image
// fills the window exactly instead of being cropped on Retina displays.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 660,
    pixelsHigh: 420,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: output)
print(output.path)
