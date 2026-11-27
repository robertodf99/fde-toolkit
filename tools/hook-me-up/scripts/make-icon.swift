// Original Hook Me Up app icon: a fishing hook and notification dot, on a blue/teal
// tile. Deterministic constants; no third-party symbols. macOS 824/1024 content box,
// 22.5% corners and a subtle shadow. Wider strokes keep the hook readable at 16/32 px.
// Usage: swift scripts/make-icon.swift <output.icns>
//        swift scripts/make-icon.swift --png <pixels> <output.png>
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

let teal = CGColor(srgbRed: 0.12, green: 0.65, blue: 0.67, alpha: 1)
let blue = CGColor(srgbRed: 0.08, green: 0.29, blue: 0.56, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let ice = CGColor(srgbRed: 0.73, green: 0.96, blue: 0.96, alpha: 1)

func renderIcon(pixels: Int) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let gradient = CGGradient(colorsSpace: space, colors: [teal, blue] as CFArray, locations: [0, 1])
    else { return nil }
    let scale = CGFloat(pixels) / 1024
    let tile = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let square = CGPath(
        roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    context.addPath(square)
    context.setFillColor(blue)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(square)
    context.clip()
    context.drawLinearGradient(
        gradient, start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    context.restoreGState()
    context.scaleBy(x: scale, y: scale)
    context.setStrokeColor(white)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(pixels <= 16 ? 96 : pixels <= 32 ? 88 : 74)
    let hook = CGMutablePath()
    hook.move(to: CGPoint(x: 590, y: 680))
    hook.addLine(to: CGPoint(x: 590, y: 420))
    hook.addCurve(to: CGPoint(x: 330, y: 420), control1: CGPoint(x: 590, y: 230), control2: CGPoint(x: 330, y: 230))
    hook.addLine(to: CGPoint(x: 330, y: 482))
    hook.addLine(to: CGPoint(x: 385, y: 428))
    context.addPath(hook)
    context.strokePath()
    context.setLineWidth(pixels <= 32 ? 50 : 42)
    context.strokeEllipse(in: CGRect(x: 532, y: 680, width: 116, height: 116))
    context.setFillColor(ice)
    context.fillEllipse(in: CGRect(x: 277, y: 662, width: 156, height: 156))
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
