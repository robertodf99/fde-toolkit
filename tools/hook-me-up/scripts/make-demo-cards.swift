// Draws the stills scripts/make-demo.sh composites the demo video from (ffmpeg here has
// no text rendering): the intro and outro cards, and one overlay per shot. An overlay is
// the brand background with the caption bar (numbered step), the progress dots and a
// shadowed, rounded-corner hole the screen recording shows through.
//
// Usage: swift scripts/make-demo-cards.swift < spec
// One card per line, fields separated by "|":
//   intro|<output.png>|<logo.png>
//   outro|<output.png>|<logo.png>
//   shot|<output.png>|<step>|<steps>|<x>|<y>|<width>|<height>|<caption>
// (x, y: the window's top-left corner in the 1920 × 1080 frame, y down)
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-demo-cards: \(message)\n".utf8))
    exit(1)
}

// MARK: Design

let canvas = CGSize(width: 1920, height: 1080)
let windowRadius: CGFloat = 18

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

// The logo's gradient (scripts/make-logo.swift) behind the shots; the social preview's
// warm near-black behind the cards.
let brandLight = srgb(0.98, 0.55, 0.33)
let brandDark = srgb(0.85, 0.30, 0.27)
let darkTop = srgb(0.17, 0.12, 0.10)
let darkBottom = srgb(0.09, 0.06, 0.06)
let glow = srgb(0.98, 0.55, 0.33, 0.28)
let accent = srgb(0.93, 0.42, 0.30)
let white = srgb(1, 1, 1)
let tagline = srgb(0.97, 0.78, 0.68)
let captionBar = srgb(0.10, 0.07, 0.06, 0.82)
let commandBox = srgb(1, 1, 1, 0.08)

// MARK: Drawing helpers (y down, like the spec; the context itself is y up)

func makeContext() -> CGContext? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    // Flip to y down for shapes; text undoes it locally.
    context?.translateBy(x: 0, y: canvas.height)
    context?.scaleBy(x: 1, y: -1)
    return context
}

func fillGradient(_ context: CGContext, from start: CGColor, to end: CGColor) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(colorsSpace: space, colors: [start, end] as CFArray, locations: [0, 1])
    else { return }
    // Top-left to bottom-right at 60° below the horizontal (y down), corner to corner along it.
    let radians: CGFloat = 60 * .pi / 180
    let direction = CGPoint(x: cos(radians), y: sin(radians))
    let reach = abs(canvas.width / 2 * direction.x) + abs(canvas.height / 2 * direction.y)
    let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
    context.drawLinearGradient(
        gradient, start: CGPoint(x: center.x - direction.x * reach, y: center.y - direction.y * reach),
        end: CGPoint(x: center.x + direction.x * reach, y: center.y + direction.y * reach), options: [])
}

func fillGlow(_ context: CGContext, at center: CGPoint, radius: CGFloat) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(
            colorsSpace: space, colors: [glow, srgb(0.98, 0.55, 0.33, 0)] as CFArray, locations: [0, 1])
    else { return }
    context.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func line(_ text: String, font: String, size: CGFloat, color: CGColor) -> CTLine {
    let ctFont = CTFontCreateWithName(font as CFString, size, nil)
    let string = NSAttributedString(
        string: text,
        attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    return CTLineCreateWithAttributedString(string)
}

func width(of line: CTLine) -> CGFloat {
    CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Draws `line` with its baseline at `baseline` (y down), starting at `x`.
func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat, in context: CGContext) {
    context.saveGState()
    context.translateBy(x: x, y: baseline)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
}

func drawCentered(_ line: CTLine, centerX: CGFloat, baseline: CGFloat, in context: CGContext) {
    draw(line, x: centerX - width(of: line) / 2, baseline: baseline, in: context)
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// The rounded logo (a PNG from make-logo.swift) with a soft shadow, `rect` y down.
func drawLogo(_ logo: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    // Shadow offsets ignore the flip (they are in the bitmap's y-up space): negative is down.
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: srgb(0, 0, 0, 0.45))
    // Undo the flip for the bitmap, which CGContext draws y up.
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(logo, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

// MARK: Cards

func intro(logo: CGImage) -> CGImage? {
    guard let context = makeContext() else { return nil }
    fillGradient(context, from: darkTop, to: darkBottom)
    let logoRect = CGRect(x: 960 - 160, y: 225, width: 320, height: 320)
    fillGlow(context, at: CGPoint(x: logoRect.midX, y: logoRect.midY), radius: 520)
    drawLogo(logo, in: logoRect, context: context)
    drawCentered(
        line("Hook Me Up", font: "Helvetica-Bold", size: 120, color: white), centerX: 960, baseline: 725,
        in: context)
    drawCentered(
        line("Answer Claude Code from your Mac\u{2019}s notifications", font: "Helvetica", size: 50, color: tagline),
        centerX: 960, baseline: 820, in: context)
    return context.makeImage()
}

func outro(logo: CGImage) -> CGImage? {
    guard let context = makeContext() else { return nil }
    fillGradient(context, from: darkTop, to: darkBottom)
    let logoRect = CGRect(x: 960 - 110, y: 200, width: 220, height: 220)
    fillGlow(context, at: CGPoint(x: logoRect.midX, y: logoRect.midY), radius: 420)
    drawLogo(logo, in: logoRect, context: context)
    drawCentered(
        line("Hook Me Up", font: "Helvetica-Bold", size: 84, color: white), centerX: 960, baseline: 550,
        in: context)

    let command = line(
        "curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | bash",
        font: "Menlo-Regular", size: 27, color: white)
    let box = CGRect(x: 960 - (width(of: command) + 72) / 2, y: 630, width: width(of: command) + 72, height: 92)
    context.addPath(roundedRect(box, 18))
    context.setFillColor(commandBox)
    context.fillPath()
    drawCentered(command, centerX: 960, baseline: box.midY + 10, in: context)
    drawCentered(
        line("github.com/robertodf99/fde-toolkit", font: "Helvetica", size: 46, color: tagline), centerX: 960,
        baseline: 860, in: context)
    return context.makeImage()
}

func shot(step: Int, steps: Int, window: CGRect, caption: String) -> CGImage? {
    guard let context = makeContext() else { return nil }
    fillGradient(context, from: brandLight, to: brandDark)

    // The window's shadow, then the hole the recording shows through.
    let hole = roundedRect(window, windowRadius)
    context.saveGState()
    // Negative is down, as in drawLogo.
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: srgb(0.25, 0.06, 0.02, 0.55))
    context.addPath(hole)
    context.setFillColor(srgb(0, 0, 0))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.setBlendMode(.clear)
    context.addPath(hole)
    context.fillPath()
    context.restoreGState()

    // Caption bar: a numbered circle and the caption, centred at the top.
    let text = line(caption, font: "Helvetica-Bold", size: 34, color: white)
    let number = line("\(step)", font: "Helvetica-Bold", size: 26, color: white)
    let barHeight: CGFloat = 68
    let circle: CGFloat = 44
    let barWidth = 12 + circle + 18 + width(of: text) + 30
    let bar = CGRect(x: (canvas.width - barWidth) / 2, y: 26, width: barWidth, height: barHeight)
    context.addPath(roundedRect(bar, barHeight / 2))
    context.setFillColor(captionBar)
    context.fillPath()
    let circleRect = CGRect(x: bar.minX + 12, y: bar.midY - circle / 2, width: circle, height: circle)
    context.setFillColor(accent)
    context.fillEllipse(in: circleRect)
    drawCentered(number, centerX: circleRect.midX, baseline: circleRect.midY + 9, in: context)
    draw(text, x: circleRect.maxX + 18, baseline: bar.midY + 12, in: context)

    // Progress dots: the current step as a wider pill.
    let gap: CGFloat = 12
    let dot: CGFloat = 10
    let current: CGFloat = 30
    let total = CGFloat(steps - 1) * (dot + gap) + current
    var x = (canvas.width - total) / 2
    for index in 1...max(steps, 1) {
        let size = index == step ? current : dot
        context.addPath(roundedRect(CGRect(x: x, y: 1046, width: size, height: dot), dot / 2))
        context.setFillColor(index == step ? white : srgb(1, 1, 1, 0.45))
        context.fillPath()
        x += size + gap
    }
    return context.makeImage()
}

func writePNG(_ image: CGImage?, to path: String) {
    guard let image,
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("could not draw \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(path)") }
}

// MARK: Spec

var count = 0
while let entry = readLine() {
    let fields = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard let kind = fields.first, !kind.isEmpty else { continue }
    switch (kind, fields.count) {
    case ("intro", 3), ("outro", 3):
        guard let logo = loadImage(fields[2]) else { fail("cannot read the logo \(fields[2])") }
        writePNG(kind == "intro" ? intro(logo: logo) : outro(logo: logo), to: fields[1])
    case ("shot", 9):
        let numbers = fields[2...7].compactMap { Int($0) }
        guard numbers.count == 6, numbers[0] >= 1, numbers[0] <= numbers[1], numbers[4] > 0, numbers[5] > 0 else {
            fail("bad shot line: \(entry)")
        }
        let window = CGRect(x: numbers[2], y: numbers[3], width: numbers[4], height: numbers[5])
        writePNG(shot(step: numbers[0], steps: numbers[1], window: window, caption: fields[8]), to: fields[1])
    default:
        fail("bad line: \(entry)")
    }
    count += 1
}
print("Demo cards: \(count) drawn")
