import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let sizes = [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (32, "icon_32x32.png"),
             (64, "icon_32x32@2x.png"), (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
             (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"), (512, "icon_512x512.png"),
             (1024, "icon_512x512@2x.png")]
for (pixels, name) in sizes {
    let s = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let plate = NSBezierPath(roundedRect: NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86),
                             xRadius: s * 0.20, yRadius: s * 0.20)
    NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.29, blue: 0.69, alpha: 1),
               ending: NSColor(calibratedRed: 0.13, green: 0.57, blue: 0.91, alpha: 1))!.draw(in: plate, angle: 75)
    let text = "K2" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.34, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2 + s * 0.02), withAttributes: attributes)
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.29, y: s * 0.24, width: s * 0.42, height: s * 0.035),
                 xRadius: s * 0.017, yRadius: s * 0.017).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
}
