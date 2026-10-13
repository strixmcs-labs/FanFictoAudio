import AppKit
import Foundation

let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = project.appendingPathComponent(".build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(calibratedRed: 143 / 255.0, green: 48 / 255.0, blue: 64 / 255.0, alpha: 1),
        ending: NSColor(calibratedRed: 63 / 255.0, green: 7 / 255.0, blue: 21 / 255.0, alpha: 1))!.draw(in: background, angle: -80)
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 220, y: 365)); left.line(to: NSPoint(x: 220, y: 720))
    left.curve(to: NSPoint(x: 492, y: 660), controlPoint1: NSPoint(x: 330, y: 748), controlPoint2: NSPoint(x: 420, y: 715))
    left.line(to: NSPoint(x: 492, y: 300))
    left.curve(to: NSPoint(x: 220, y: 365), controlPoint1: NSPoint(x: 400, y: 360), controlPoint2: NSPoint(x: 320, y: 395)); left.close()
    NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.86, alpha: 1).setFill(); left.fill()
    let right = NSBezierPath()
    right.move(to: NSPoint(x: 532, y: 300)); right.line(to: NSPoint(x: 532, y: 660))
    right.curve(to: NSPoint(x: 804, y: 720), controlPoint1: NSPoint(x: 610, y: 715), controlPoint2: NSPoint(x: 700, y: 748))
    right.line(to: NSPoint(x: 804, y: 365))
    right.curve(to: NSPoint(x: 532, y: 300), controlPoint1: NSPoint(x: 700, y: 395), controlPoint2: NSPoint(x: 620, y: 360)); right.close()
    NSColor(calibratedRed: 1, green: 0.98, blue: 0.92, alpha: 1).setFill(); right.fill()
    let waveform = NSBezierPath()
    waveform.lineWidth = 22
    waveform.lineCapStyle = .round
    for (index, height) in [48.0, 100, 156, 88, 130, 60].enumerated() {
        let x = 604.0 + Double(index) * 29
        waveform.move(to: NSPoint(x: x, y: 518 - height / 2))
        waveform.line(to: NSPoint(x: x, y: 518 + height / 2))
    }
    NSColor(calibratedRed: 101 / 255.0, green: 15 / 255.0, blue: 32 / 255.0, alpha: 1).setStroke(); waveform.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let filename = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
        try drawIcon(size: points * factor).write(to: iconset.appendingPathComponent(filename))
    }
}
print(iconset.path)
