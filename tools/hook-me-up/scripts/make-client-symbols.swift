// Renders the committed, path-only client symbols. These identify notification
// origins only; the app icon and project branding never use third-party symbols.
// Usage: swift scripts/make-client-symbols.swift <icon-source-folder> <output-folder>
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-client-symbols: \(message)\n".utf8))
    exit(1)
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
            FileHandle.standardError.write(Data("make-client-symbols: unsupported path command \(command)\n".utf8))
            exit(1)
        }
    }
    return path
}

// Claude's source fill is hsl(14.8, 63.1%, 59.6%); the Blossom's default fill is black.
let claudeColor = CGColor(srgbRed: 0.850924000000, green: 0.466838506667, blue: 0.341076000000, alpha: 1)
let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("expected <icon-source-folder> <output-folder>") }
let source = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
for (file, name, viewport, color) in [
    ("claude-symbol.svg", "notification-claude", CGRect(x: 0, y: 0, width: 100, height: 100), claudeColor),
    ("openai-blossom.svg", "notification-codex", CGRect(x: 1.68, y: 1.75, width: 16.65, height: 16.5), black),
] {
    guard let svg = try? String(contentsOf: source.appendingPathComponent(file), encoding: .utf8) else {
        fail("cannot read \(file)")
    }
    let glyph = pathData(in: svg).map { path(from: $0) }
    guard !glyph.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("cannot render \(file)") }
    // A small mark with equal clear space on plain white; preserve its aspect ratio.
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    let unit = 64 / max(viewport.width, viewport.height)
    context.translateBy(x: 64 - viewport.midX * unit, y: 64 + viewport.midY * unit)
    context.scaleBy(x: unit, y: -unit)
    for segment in glyph { context.addPath(segment) }
    context.setFillColor(color)
    context.fillPath()
    guard let image = context.makeImage(),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fail("cannot encode \(file)") }
    do { try png.write(to: output.appendingPathComponent(name + ".png")) } catch {
        fail("cannot write \(name): \(error)")
    }
    print("Client symbol: \(name).png (128 x 128)")
}
