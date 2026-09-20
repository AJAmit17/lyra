// Renders the Lyra app icon: the constellation, on a night gradient.
// Usage: xcrun swift scripts/icon.swift   (writes mac/Resources/Lyra.icns and the iOS asset)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

/// Lyra: Vega, then the lyre's body. Normalised to the drawing area.
let stars: [(x: Double, y: Double, r: Double)] = [
    (0.30, 0.16, 0.052),  // Vega
    (0.46, 0.35, 0.026),
    (0.70, 0.29, 0.030),
    (0.76, 0.62, 0.026),
    (0.52, 0.74, 0.030),
    (0.38, 0.55, 0.024),
]
let lines = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 1)]

func draw(size: Int, inset: Double, corner: Double) -> NSBitmapImageRep {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    let margin = side * CGFloat(inset)
    let plate = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let radius = plate.width * CGFloat(corner)
    let shape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.08, green: 0.06, blue: 0.22, alpha: 1),
                                       CGColor(red: 0.29, green: 0.16, blue: 0.62, alpha: 1),
                                       CGColor(red: 0.13, green: 0.55, blue: 0.62, alpha: 1)] as CFArray,
                              locations: [0, 0.62, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                               end: CGPoint(x: plate.maxX, y: plate.minY), options: [])

    // The constellation sits inside the plate, with the y axis flipped to read top-down.
    func point(_ star: (x: Double, y: Double, r: Double)) -> CGPoint {
        CGPoint(x: plate.minX + plate.width * CGFloat(star.x),
                y: plate.maxY - plate.height * CGFloat(star.y))
    }

    context.setStrokeColor(CGColor(gray: 1, alpha: 0.42))
    context.setLineWidth(max(1, plate.width * 0.012))
    context.setLineCap(.round)
    for (from, to) in lines {
        context.move(to: point(stars[from]))
        context.addLine(to: point(stars[to]))
    }
    context.strokePath()

    for star in stars {
        let centre = point(star)
        let radius = plate.width * CGFloat(star.r)
        context.setShadow(offset: .zero, blur: radius * 1.6, color: CGColor(gray: 1, alpha: 0.9))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))
    }
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// macOS: Apple's grid leaves a margin around the plate and uses the squircle radius.
let iconset = root.appendingPathComponent("mac/.build/Lyra.iconset")
try? FileManager.default.removeItem(at: iconset)
for size in [16, 32, 128, 256, 512] {
    try write(draw(size: size, inset: 0.10, corner: 0.223),
              to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try write(draw(size: size * 2, inset: 0.10, corner: 0.223),
              to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let icns = root.appendingPathComponent("mac/Resources/Lyra.icns")
let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try convert.run()
convert.waitUntilExit()

// iOS: full bleed, the system applies the mask.
try write(draw(size: 1024, inset: 0, corner: 0),
          to: root.appendingPathComponent("ios/Lyra/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
print("Wrote \(icns.path) and the iOS app icon.")
