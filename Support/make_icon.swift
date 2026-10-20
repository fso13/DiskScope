import AppKit
import CoreGraphics
import Foundation

// Draws the app icon as a 1024x1024 PNG: a gradient squircle with a treemap.
// Usage: make-icon <output.png>

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let side = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Unable to create bitmap context\n".utf8))
    exit(1)
}

context.setAllowsAntialiasing(true)
context.clear(CGRect(x: 0, y: 0, width: side, height: side))

let background = CGRect(x: 62, y: 62, width: 900, height: 900)
let backgroundPath = CGPath(
    roundedRect: background,
    cornerWidth: 208,
    cornerHeight: 208,
    transform: nil
)

// Drop shadow under the squircle.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -16),
    blur: 36,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
)
context.addPath(backgroundPath)
context.setFillColor(CGColor(red: 0.34, green: 0.47, blue: 1.0, alpha: 1))
context.fillPath()
context.restoreGState()

// Gradient fill.
context.saveGState()
context.addPath(backgroundPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.34, green: 0.54, blue: 1.0, alpha: 1),
        CGColor(red: 0.56, green: 0.27, blue: 0.94, alpha: 1),
        CGColor(red: 0.40, green: 0.22, blue: 0.82, alpha: 1),
    ] as CFArray,
    locations: [0, 0.58, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: background.minX, y: background.maxY),
    end: CGPoint(x: background.maxX, y: background.minY),
    options: []
)

let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: background.minX + 240, y: background.maxY - 150),
    startRadius: 10,
    endCenter: CGPoint(x: background.minX + 240, y: background.maxY - 150),
    endRadius: 560,
    options: []
)
context.restoreGState()

// Treemap tiles.
let inset: CGFloat = 132
let inner = background.insetBy(dx: inset, dy: inset)
let gap: CGFloat = 20
let leftWidth = (inner.width - gap) * 0.56
let rightX = inner.minX + leftWidth + gap
let rightWidth = inner.width - leftWidth - gap
let topHeight = (inner.height - gap) * 0.58
let bottomHeight = inner.height - topHeight - gap
let bottomWidth = (rightWidth - gap) / 2

func tile(_ rect: CGRect, alpha: CGFloat) {
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: 30,
        cornerHeight: 30,
        transform: nil
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -6),
        blur: 14,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.16)
    )
    context.addPath(path)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    context.fillPath()
    context.restoreGState()
}

tile(CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: inner.height), alpha: 0.95)
tile(CGRect(x: rightX, y: inner.minY + bottomHeight + gap, width: rightWidth, height: topHeight), alpha: 0.76)
tile(CGRect(x: rightX, y: inner.minY, width: bottomWidth, height: bottomHeight), alpha: 0.54)
tile(
    CGRect(x: rightX + bottomWidth + gap, y: inner.minY, width: bottomWidth, height: bottomHeight),
    alpha: 0.37
)

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("Unable to create image\n".utf8))
    exit(1)
}

let representation = NSBitmapImageRep(cgImage: image)
guard let data = representation.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Unable to encode PNG\n".utf8))
    exit(1)
}

do {
    try data.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath)")
} catch {
    FileHandle.standardError.write(Data("Unable to write icon: \(error)\n".utf8))
    exit(1)
}
