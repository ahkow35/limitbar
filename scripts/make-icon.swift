import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shape = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194)
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.22, alpha: 1),
                   ending: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.11, alpha: 1))!.draw(in: shape, angle: -60)
        NSColor.white.withAlphaComponent(0.10).setStroke()
        shape.lineWidth = 4
        shape.stroke()
        for (index, height) in [260.0, 480.0, 360.0].enumerated() {
            let x = 253 + Double(index) * 185
            NSColor(srgbRed: 0.55, green: 0.84, blue: 0.73, alpha: 0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 270, width: 135, height: 480), xRadius: 54, yRadius: 54).fill()
            let color = index == 0 ? NSColor(srgbRed: 0.88, green: 0.57, blue: 0.43, alpha: 1)
                                  : NSColor(srgbRed: 0.55, green: 0.84, blue: 0.73, alpha: 1)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 270, width: 135, height: height), xRadius: 54, yRadius: 54).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
