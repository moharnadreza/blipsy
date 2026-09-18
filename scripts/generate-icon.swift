import AppKit

// Draws blipsy's app icon (concept #3: glossy green status dot on a light squircle)
// at all required sizes, writes an .iconset, ready for `iconutil`.

func makeIcon(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpaceCreateDeviceRGB()

    // Rounded-rect (squircle-ish) light background.
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let corner = rect.width * 0.2237
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.957, green: 0.965, blue: 0.980, alpha: 1).cgColor,
        NSColor(srgbRed: 0.875, green: 0.894, blue: 0.925, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Glossy green dot.
    let r = size * 0.235
    let c = CGPoint(x: size / 2, y: size / 2)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.clip()
    let dot = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.482, green: 0.910, blue: 0.604, alpha: 1).cgColor,
        NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1).cgColor,
        NSColor(srgbRed: 0.122, green: 0.616, blue: 0.263, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(dot,
                           startCenter: CGPoint(x: c.x - r * 0.3, y: c.y + r * 0.3), startRadius: 0,
                           endCenter: c, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // Soft top highlight for gloss.
    ctx.saveGState()
    ctx.setFillColor(NSColor(white: 1, alpha: 0.33).cgColor)
    ctx.addEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.15, width: r, height: r * 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = "build/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    try! makeIcon(px).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("wrote \(iconset) (\(specs.count) images)")
