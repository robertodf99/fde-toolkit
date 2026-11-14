// Draws the app icon: the Claude symbol (Wikimedia Commons, CC0; see
// THIRD_PARTY_NOTICES.md) as a white spark on a clay (#D97757) rounded square, in the
// macOS app-icon style (the 824/1024 content box, 22.5% corners, a subtle shadow), at
// every size an .icns holds. Only the committed SVG path and the constants below go
// into it, so every build draws the same icon.
//
// Usage: swift scripts/make-icon.swift <symbol.svg> <output.icns>
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <glyph.svg> <output.icns>\n".utf8))
    exit(2)
}

// MARK: Design

let clay = CGColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

/// How much of the tile the spark spans: a little more at the smallest sizes, so its rays
/// stay readable.
func sparkShare(pixels: Int) -> CGFloat {
    switch pixels {
    case ...16: 0.68
    case ...32: 0.64
    default: 0.58
    }
}

// MARK: SVG path data (M, L, H, V, C, S, Q, A, Z, absolute and relative)

/// The `d` attributes of the SVG's <path> elements.
func pathData(in svg: String) -> [String] {
    var result: [String] = []
    var rest = svg[...]
    while let start = rest.range(of: "d=\"") {
        let afterStart = rest[start.upperBound...]
        guard let end = afterStart.firstIndex(of: "\"") else { break }
        result.append(String(afterStart[..<end]))
        rest = afterStart[afterStart.index(after: end)...]
    }
    return result
}

/// Reads path data: command letters, numbers, and the one-digit arc flags.
struct Scanner {
    let characters: [Character]
    var index = 0

    init(_ text: String) { characters = Array(text) }

    mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," { index += 1 }
    }

    mutating func command() -> Character? {
        skipSeparators()
        guard index < characters.count, characters[index].isLetter else { return nil }
        defer { index += 1 }
        return characters[index]
    }

    var atNumber: Bool {
        var probe = self
        probe.skipSeparators()
        guard probe.index < characters.count else { return false }
        let character = probe.characters[probe.index]
        return character.isNumber || character == "-" || character == "+" || character == "."
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
        var seenDot = false
        var seenExponent = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                index += 1
            } else if character == ".", !seenDot, !seenExponent {
                seenDot = true
                index += 1
            } else if character == "e" || character == "E", !seenExponent {
                seenExponent = true
                index += 1
                if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            } else {
                break
            }
        }
        guard index > start, let value = Double(String(characters[start..<index])) else { return nil }
        return CGFloat(value)
    }

    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < characters.count, characters[index] == "0" || characters[index] == "1" else { return nil }
        defer { index += 1 }
        return characters[index] == "1"
    }
}

/// Appends an SVG elliptical arc as cubic Béziers (SVG 1.1, appendix F.6.5).
func addArc(
    to path: CGMutablePath, from p0: CGPoint, radii: CGPoint, rotation: CGFloat, largeArc: Bool, sweep: Bool,
    to p1: CGPoint
) {
    var rx = abs(radii.x)
    var ry = abs(radii.y)
    guard rx > 0, ry > 0, p0 != p1 else {
        path.addLine(to: p1)
        return
    }
    let phi = rotation * .pi / 180
    let (cosPhi, sinPhi) = (cos(phi), sin(phi))
    let dx = (p0.x - p1.x) / 2
    let dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
        rx *= lambda.squareRoot()
        ry *= lambda.squareRoot()
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let coefficient = (largeArc != sweep ? 1 : -1) * max(0, numerator / denominator).squareRoot()
    let cx1 = coefficient * rx * y1 / ry
    let cy1 = -coefficient * ry * x1 / rx
    let center = CGPoint(
        x: cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2, y: sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2)
    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let start = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    // The unit circle, scaled, rotated and moved onto the ellipse.
    let toEllipse = CGAffineTransform(
        a: cosPhi * rx, b: sinPhi * rx, c: -sinPhi * ry, d: cosPhi * ry, tx: center.x, ty: center.y)
    let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / CGFloat(segments)
    let k = 4 / 3 * tan(step / 4)
    for segment in 0..<segments {
        let a = start + CGFloat(segment) * step
        let b = a + step
        let control1 = CGPoint(x: cos(a) - k * sin(a), y: sin(a) + k * cos(a)).applying(toEllipse)
        let control2 = CGPoint(x: cos(b) + k * sin(b), y: sin(b) - k * cos(b)).applying(toEllipse)
        let end = segment == segments - 1 ? p1 : CGPoint(x: cos(b), y: sin(b)).applying(toEllipse)
        path.addCurve(to: end, control1: control1, control2: control2)
    }
}

/// One SVG path as a CGPath, in the SVG's own coordinates (y down).
func path(from data: String) -> CGMutablePath {
    let path = CGMutablePath()
    var scanner = Scanner(data)
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var lastControl: CGPoint?
    var command: Character = "M"
    while true {
        if let next = scanner.command() {
            command = next
        } else if !scanner.atNumber {
            break
        }
        let relative = command.isLowercase
        func point() -> CGPoint {
            let x = scanner.number() ?? 0
            let y = scanner.number() ?? 0
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        switch command.uppercased() {
        case "M":
            current = point()
            subpathStart = current
            path.move(to: current)
            command = relative ? "l" : "L"  // further pairs are lines
            lastControl = nil
        case "L":
            current = point()
            path.addLine(to: current)
            lastControl = nil
        case "H":
            let x = scanner.number() ?? 0
            current.x = relative ? current.x + x : x
            path.addLine(to: current)
            lastControl = nil
        case "V":
            let y = scanner.number() ?? 0
            current.y = relative ? current.y + y : y
            path.addLine(to: current)
            lastControl = nil
        case "C":
            let control1 = point()
            let control2 = point()
            let end = point()
            path.addCurve(to: end, control1: control1, control2: control2)
            lastControl = control2
            current = end
        case "S":
            let control1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
            let control2 = point()
            let end = point()
            path.addCurve(to: end, control1: control1, control2: control2)
            lastControl = control2
            current = end
        case "Q":
            let control = point()
            let end = point()
            path.addQuadCurve(to: end, control: control)
            lastControl = nil
            current = end
        case "A":
            let radii = CGPoint(x: scanner.number() ?? 0, y: scanner.number() ?? 0)
            let rotation = scanner.number() ?? 0
            let largeArc = scanner.flag() ?? false
            let sweep = scanner.flag() ?? false
            let end = point()
            addArc(to: path, from: current, radii: radii, rotation: rotation, largeArc: largeArc, sweep: sweep, to: end)
            lastControl = nil
            current = end
        case "Z":
            path.closeSubpath()
            current = subpathStart
            lastControl = nil
            if !scanner.atNumber { continue }
        default:
            FileHandle.standardError.write(Data("make-icon: unsupported path command \(command)\n".utf8))
            exit(1)
        }
    }
    return path
}

// MARK: Drawing

/// The icon at `pixels` × `pixels`.
func renderIcon(pixels: Int, glyph: [CGPath]) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let scale = CGFloat(pixels) / 1024
    let tile = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let square = CGPath(
        roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

    // The clay square with a subtle shadow.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    context.addPath(square)
    context.setFillColor(clay)
    context.fillPath()
    context.restoreGState()

    // The spark, centred on its own bounds, y flipped (SVG is y down).
    let bounds = glyph.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
    guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
    let unit = tile.width * sparkShare(pixels: pixels) / max(bounds.width, bounds.height)
    context.saveGState()
    context.translateBy(x: tile.midX - bounds.midX * unit, y: tile.midY + bounds.midY * unit)
    context.scaleBy(x: unit, y: -unit)
    for path in glyph { context.addPath(path) }
    context.setFillColor(white)
    context.fillPath()
    context.restoreGState()
    return context.makeImage()
}

// MARK: .icns, assembled by iconutil from an iconset

let iconsetFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

guard let svg = try? String(contentsOfFile: arguments[1], encoding: .utf8) else { fail("cannot read \(arguments[1])") }
let glyph = pathData(in: svg).map { path(from: $0) }
guard !glyph.isEmpty else { fail("no <path> in \(arguments[1])") }

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-icon-\(UUID().uuidString).iconset")
do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
} catch {
    fail("cannot create \(iconset.path): \(error)")
}
defer { try? FileManager.default.removeItem(at: iconset) }
for file in iconsetFiles {
    guard let image = renderIcon(pixels: file.pixels, glyph: glyph),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
        (try? png.write(to: iconset.appendingPathComponent(file.name))) != nil
    else { fail("could not draw the \(file.pixels)-pixel icon") }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", arguments[2], iconset.path]
do {
    try iconutil.run()
} catch {
    fail("cannot run iconutil: \(error)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil could not write \(arguments[2])") }
print("Icon: \(arguments[1]) (\(glyph.count) paths) -> \(arguments[2])")
