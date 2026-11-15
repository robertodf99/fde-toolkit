// Draws the project logo (a notification card on a warm gradient, with a fishing hook
// hanging from it) and the images made from it: the README logo, GitHub's social
// preview and a square Product Hunt thumbnail. The app icon is a different picture,
// drawn by scripts/make-icon.swift. Only the constants below go into the images, so
// every run draws the same files.
//
// Usage: swift scripts/make-logo.swift <output-folder>
//          writes logo.png (256 px, rounded corners), social-preview.png (1280 × 640)
//          and product-hunt-thumbnail.png (960 px, square corners)
//        swift scripts/make-logo.swift --logo <pixels> <output.png>
//          writes the rounded logo alone at that size (scripts/make-demo.sh uses it)
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-logo: \(message)\n".utf8))
    exit(1)
}

func usage() -> Never {
    FileHandle.standardError.write(
        Data("usage: make-logo.swift <output-folder> | make-logo.swift --logo <pixels> <output.png>\n".utf8))
    exit(2)
}

// MARK: Design (in a 480-unit square, y up)

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let logoUnits: CGFloat = 480
let gradientStart = srgb(0.98, 0.55, 0.33)
let gradientEnd = srgb(0.85, 0.30, 0.27)
let gradientAngle: CGFloat = -60  // degrees, from the light corner (top left) to the dark one
let white = srgb(1, 1, 1)
let appSquare = srgb(0.93, 0.42, 0.30)
let titleBar = srgb(0.20, 0.20, 0.20)
let bodyBar = srgb(0.78, 0.78, 0.78)

/// The social preview's background: a warm near-black, so the orange logo stands out.
let darkTop = srgb(0.17, 0.12, 0.10)
let darkBottom = srgb(0.09, 0.06, 0.06)
let glow = srgb(0.98, 0.55, 0.33, 0.30)
let tagline = srgb(0.97, 0.78, 0.68)

/// Fills `rect` with a linear gradient at `angle` degrees, its ends on the rect's
/// extreme corners along that direction (as NSGradient's draw(in:angle:) does).
func fillGradient(_ context: CGContext, _ rect: CGRect, from start: CGColor, to end: CGColor, angle: CGFloat) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(colorsSpace: space, colors: [start, end] as CFArray, locations: [0, 1])
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

/// The logo in the square `frame`; `rounded` clips it to a rounded square (22.5% corners).
func drawLogo(_ context: CGContext, in frame: CGRect, rounded: Bool) {
    let unit = frame.width / logoUnits
    context.saveGState()
    if rounded {
        let radius = frame.width * 0.225
        context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }
    fillGradient(context, frame, from: gradientStart, to: gradientEnd, angle: gradientAngle)
    context.translateBy(x: frame.minX, y: frame.minY)
    context.scaleBy(x: unit, y: unit)

    // The notification card, with a soft shadow (shadows ignore the scale, so it is applied by hand).
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -8 * unit), blur: 24 * unit, color: srgb(0, 0, 0, 0.25))
    fillRoundedRect(context, CGRect(x: 60, y: 250, width: 360, height: 130), radius: 28, color: white)
    context.restoreGState()

    // The card's app square and two lines of text.
    fillRoundedRect(context, CGRect(x: 84, y: 289, width: 52, height: 52), radius: 13, color: appSquare)
    fillRoundedRect(context, CGRect(x: 156, y: 320, width: 200, height: 18), radius: 9, color: titleBar)
    fillRoundedRect(context, CGRect(x: 156, y: 292, width: 140, height: 14), radius: 7, color: bodyBar)

    // The hook hanging from the card's bottom edge: shank, bend, rising point, then the barb.
    context.setStrokeColor(white)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let hook = CGMutablePath()
    hook.move(to: CGPoint(x: 260, y: 250))
    hook.addLine(to: CGPoint(x: 260, y: 150))
    hook.addArc(center: CGPoint(x: 210, y: 150), radius: 50, startAngle: 0, endAngle: .pi, clockwise: true)
    hook.addLine(to: CGPoint(x: 160, y: 185))
    context.addPath(hook)
    context.setLineWidth(26)
    context.strokePath()
    let barb = CGMutablePath()
    barb.move(to: CGPoint(x: 160, y: 190))
    barb.addLine(to: CGPoint(x: 185, y: 165))
    context.addPath(barb)
    context.setLineWidth(22)
    context.strokePath()
    context.restoreGState()
}

// MARK: Text (Core Text; Helvetica ships with macOS)

func attributed(_ text: String, font: String, size: CGFloat, color: CGColor) -> NSAttributedString {
    let ctFont = CTFontCreateWithName(font as CFString, size, nil)
    return NSAttributedString(
        string: text,
        attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
}

/// Draws `lines` left-aligned from `origin` (the first baseline), `leading` apart.
func drawLines(_ context: CGContext, _ lines: [NSAttributedString], origin: CGPoint, leading: CGFloat) {
    for (index, line) in lines.enumerated() {
        context.textPosition = CGPoint(x: origin.x, y: origin.y - CGFloat(index) * leading)
        CTLineDraw(CTLineCreateWithAttributedString(line), context)
    }
}

// MARK: Images

/// An sRGB bitmap; `opaque` leaves out the alpha channel (smaller PNGs).
func makeContext(width: Int, height: Int, opaque: Bool = false) -> CGContext? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    return CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: alpha.rawValue)
}

func logoImage(pixels: Int, rounded: Bool) -> CGImage? {
    guard let context = makeContext(width: pixels, height: pixels, opaque: !rounded) else { return nil }
    drawLogo(context, in: CGRect(x: 0, y: 0, width: pixels, height: pixels), rounded: rounded)
    return context.makeImage()
}

func socialPreview() -> CGImage? {
    let size = CGSize(width: 1280, height: 640)
    guard let context = makeContext(width: Int(size.width), height: Int(size.height), opaque: true),
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let halo = CGGradient(
            colorsSpace: space, colors: [glow, srgb(0.98, 0.55, 0.33, 0)] as CFArray, locations: [0, 1])
    else { return nil }
    fillGradient(context, CGRect(origin: .zero, size: size), from: darkTop, to: darkBottom, angle: -60)
    let logo = CGRect(x: 110, y: 140, width: 360, height: 360)
    context.drawRadialGradient(
        halo, startCenter: CGPoint(x: logo.midX, y: logo.midY), startRadius: 0,
        endCenter: CGPoint(x: logo.midX, y: logo.midY), endRadius: 380, options: [])
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: srgb(0, 0, 0, 0.45))
    let radius = logo.width * 0.225
    fillRoundedRect(context, logo, radius: radius, color: gradientEnd)
    context.restoreGState()
    drawLogo(context, in: logo, rounded: true)

    let textX: CGFloat = 540
    drawLines(
        context, [attributed("Hook Me Up", font: "Helvetica-Bold", size: 112, color: white)],
        origin: CGPoint(x: textX, y: 352), leading: 0)
    drawLines(
        context,
        [
            attributed("Answer Claude Code from", font: "Helvetica", size: 46, color: tagline),
            attributed("your Mac\u{2019}s notifications", font: "Helvetica", size: 46, color: tagline),
        ],
        origin: CGPoint(x: textX + 4, y: 268), leading: 58)
    return context.makeImage()
}

func writePNG(_ image: CGImage?, to path: String) {
    guard let image,
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("could not draw \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(path)") }
    print("Logo: \(path) (\(image.width) x \(image.height))")
}

let arguments = CommandLine.arguments
switch arguments.count {
case 2:
    let folder = URL(fileURLWithPath: arguments[1])
    writePNG(logoImage(pixels: 256, rounded: true), to: folder.appendingPathComponent("logo.png").path)
    writePNG(socialPreview(), to: folder.appendingPathComponent("social-preview.png").path)
    writePNG(
        logoImage(pixels: 960, rounded: false),
        to: folder.appendingPathComponent("product-hunt-thumbnail.png").path)
case 4 where arguments[1] == "--logo":
    guard let pixels = Int(arguments[2]), (16...4096).contains(pixels) else { usage() }
    writePNG(logoImage(pixels: pixels, rounded: true), to: arguments[3])
default:
    usage()
}
