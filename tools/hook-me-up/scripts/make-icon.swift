// Draws the same notification-card logo as scripts/make-logo.swift in the macOS app-icon
// tile: 824/1024 content, 22.5% corners and a subtle shadow. Constants and shapes match
// drawLogo; the hook stroke is slightly thicker at 16 px for legibility. Deterministic.
// Usage: swift scripts/make-icon.swift <output.icns>
//        swift scripts/make-icon.swift --png <pixels> <output.png>
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

// These logo design constants and drawLogo geometry match make-logo.swift.
let logoUnits: CGFloat = 480
let gradientStart = CGColor(srgbRed: 0.12, green: 0.65, blue: 0.67, alpha: 1)
let gradientEnd = CGColor(srgbRed: 0.08, green: 0.29, blue: 0.56, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let appSquare = CGColor(srgbRed: 0.10, green: 0.48, blue: 0.62, alpha: 1)
let titleBar = CGColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1)
let bodyBar = CGColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1)

func fillGradient(_ context: CGContext, _ rect: CGRect, angle: CGFloat) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(
            colorsSpace: space, colors: [gradientStart, gradientEnd] as CFArray, locations: [0, 1])
    else { return }
    let radians = angle * .pi / 180
    let direction = CGPoint(x: cos(radians), y: sin(radians))
    let reach = abs(rect.width / 2 * direction.x) + abs(rect.height / 2 * direction.y)
    let from = CGPoint(x: rect.midX - direction.x * reach, y: rect.midY - direction.y * reach)
    let to = CGPoint(x: rect.midX + direction.x * reach, y: rect.midY + direction.y * reach)
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(gradient, start: from, end: to, options: [])
    context.restoreGState()
}

func fillRoundedRect(_ context: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(color)
    context.fillPath()
}

/// The project logo drawing, scaled to `frame` and clipped to macOS's rounded tile.
func drawLogo(_ context: CGContext, in frame: CGRect, pixels: Int) {
    let unit = frame.width / logoUnits
    let radius = frame.width * 0.225
    context.saveGState()
    context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    fillGradient(context, frame, angle: -60)
    context.translateBy(x: frame.minX, y: frame.minY)
    context.scaleBy(x: unit, y: unit)

    // The notification card, with the same soft shadow as the project logo.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -8 * unit), blur: 24 * unit,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
    fillRoundedRect(context, CGRect(x: 60, y: 250, width: 360, height: 130), radius: 28, color: white)
    context.restoreGState()

    // The logo's app square and two text bars; slightly taller bars survive rasterization at 16 px.
    fillRoundedRect(context, CGRect(x: 84, y: 289, width: 52, height: 52), radius: 13, color: appSquare)
    let titleHeight: CGFloat = pixels <= 16 ? 30 : 18
    let bodyHeight: CGFloat = pixels <= 16 ? 26 : 14
    fillRoundedRect(
        context, CGRect(x: 156, y: 320 - (titleHeight - 18) / 2, width: 200, height: titleHeight),
        radius: titleHeight / 2, color: titleBar)
    fillRoundedRect(
        context, CGRect(x: 156, y: 292 - (bodyHeight - 14) / 2, width: 140, height: bodyHeight),
        radius: bodyHeight / 2, color: bodyBar)

    // The same hook path as drawLogo. Only its tiny-size stroke changes for legibility.
    context.setStrokeColor(white)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let hook = CGMutablePath()
    hook.move(to: CGPoint(x: 260, y: 250))
    hook.addLine(to: CGPoint(x: 260, y: 150))
    hook.addArc(center: CGPoint(x: 210, y: 150), radius: 50, startAngle: 0, endAngle: .pi, clockwise: true)
    hook.addLine(to: CGPoint(x: 160, y: 185))
    context.addPath(hook)
    context.setLineWidth(pixels <= 16 ? 38 : 26)
    context.strokePath()
    let barb = CGMutablePath()
    barb.move(to: CGPoint(x: 160, y: 190))
    barb.addLine(to: CGPoint(x: 185, y: 165))
    context.addPath(barb)
    context.setLineWidth(pixels <= 16 ? 32 : 22)
    context.strokePath()
    context.restoreGState()
}

func renderIcon(pixels: Int) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / 1024
    let tile = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let radius = tile.width * 0.225
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    fillRoundedRect(context, tile, radius: radius, color: gradientEnd)
    context.restoreGState()
    drawLogo(context, in: tile, pixels: pixels)
    return context.makeImage()
}

func writePNG(pixels: Int, to url: URL) {
    guard let image = renderIcon(pixels: pixels),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
        (try? png.write(to: url)) != nil
    else { fail("could not draw the \(pixels)-pixel icon") }
}

let iconsetFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "--png", let pixels = Int(arguments[2]), (16...4096).contains(pixels) {
    writePNG(pixels: pixels, to: URL(fileURLWithPath: arguments[3]))
    exit(0)
}
guard arguments.count == 2 else { fail("expected <output.icns> or --png <pixels> <output.png>") }
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-icon-\(UUID().uuidString).iconset")
do { try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false) } catch {
    fail("cannot create iconset: \(error)")
}
defer { try? FileManager.default.removeItem(at: iconset) }
for file in iconsetFiles { writePNG(pixels: file.pixels, to: iconset.appendingPathComponent(file.name)) }
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", arguments[1], iconset.path]
do { try iconutil.run() } catch { fail("cannot run iconutil: \(error)") }
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil could not write \(arguments[1])") }
print("Icon: \(arguments[1])")
