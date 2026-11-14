import AppKit
import CoreImage

/// Makes the app icon at build or install time; no image is ever committed. With the
/// Claude app installed it is that app's own icon as macOS shows it (the asset-catalog
/// icon named by CFBundleIconName, else its CFBundleIconFile). Otherwise it draws a
/// dark spark on a clay (#D97757) rounded square, the spark taken from the Claude app's
/// tray icon, or the ✻ glyph when there is none.
@MainActor
enum AppIcon {
    /// The .icns entries: the element type of each size, PNG data in every one.
    static let entries: [(type: String, pixels: Int)] = [
        ("ic04", 16), ("ic11", 32), ("ic05", 32), ("ic12", 64), ("ic07", 128),
        ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
    ]

    /// Writes `output` (.icns) from the Claude app at `claudeApp` (nil: none) and returns
    /// which source was used, for the build log.
    static func write(claudeApp: String?, to output: URL) throws -> String {
        let official = claudeApp.flatMap(officialIcon(appPath:))
        let template =
            official == nil
            ? claudeApp.flatMap { loadTemplate("\($0)/Contents/Resources/TrayIconTemplate@3x.png") } : nil
        var body = Data()
        for entry in entries {
            let rendered =
                if let official { render(official.image, pixels: entry.pixels) } else {
                    drawnIcon(pixels: entry.pixels, template: template)
                }
            guard let rendered,
                let png = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
            else { throw AppIconError.renderFailed(entry.pixels) }
            body += Data(entry.type.utf8) + bigEndian(UInt32(8 + png.count)) + png
        }
        let icns = Data("icns".utf8) + bigEndian(UInt32(8 + body.count)) + body
        do {
            try icns.write(to: output, options: .atomic)
        } catch {
            throw AppIconError.writeFailed(output.path)
        }
        if let official { return "official icon from the installed Claude app (\(official.source))" }
        return template == nil ? "✻ fallback (Claude app not found)" : "spark from the installed Claude app"
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// The installed Claude app's own icon, and where it came from.
    private static func officialIcon(appPath: String) -> (image: NSImage, source: String)? {
        guard let bundle = Bundle(path: appPath) else { return nil }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            let image = bundle.image(forResource: name), image.isValid
        {
            return (image, "asset catalog icon \(name)")
        }
        if let file = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
            let url = bundle.url(forResource: (file as NSString).deletingPathExtension, withExtension: "icns"),
            let image = NSImage(contentsOf: url), image.isValid
        {
            return (image, file)
        }
        return nil
    }

    /// `icon` drawn at `pixels` × `pixels`.
    private static func render(_ icon: NSImage, pixels: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static let clay = CGColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    private static let ink = (red: 0x1F / 255.0, green: 0x1E / 255.0, blue: 0x1D / 255.0)

    /// The tray icon's silhouette (black on transparent), if it can be read.
    private static func loadTemplate(_ path: String) -> CGImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// The template's ink coverage (0 = none, 1 = full) as a grey image, cropped to the
    /// spark's bounds so the spark fills the space it is given.
    private static func coverage(of template: CGImage) -> CIImage? {
        let width = template.width
        let height = template.height
        guard
            let gray = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        gray.setFillColor(gray: 1, alpha: 1)
        gray.fill(CGRect(x: 0, y: 0, width: width, height: height))
        gray.draw(template, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = gray.data, let image = gray.makeImage() else { return nil }
        let samples = data.bindMemory(to: UInt8.self, capacity: width * height)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where samples[y * width + x] < 250 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Inverted so ink is white; CoreImage's origin is bottom-left, the buffer's top-left.
        let bounds = CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
        return CIImage(cgImage: image).applyingFilter("CIColorInvert").cropped(to: bounds)
            .transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }

    /// The spark in ink, fitted in `side` × `side` pixels. When enlarging the small
    /// template, its edge is smoothed (Lanczos, then a light blur) and sharpened again, so
    /// the silhouette is crisp instead of stair-stepped.
    private static func spark(from template: CGImage, side: Int) -> CGImage? {
        guard let ink0 = coverage(of: template), let rgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // A margin inside the canvas keeps the smoothed ray tips whole.
        let scale = CGFloat(side) * 0.94 / max(ink0.extent.width, ink0.extent.height)
        let enlarging = scale > 1
        var scaled = ink0.composited(over: CIImage(color: .black))
            .cropped(to: ink0.extent.insetBy(dx: -4, dy: -4))
            .applyingFilter(
                "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        if enlarging { scaled = scaled.applyingGaussianBlur(sigma: Double(scale) * 0.35) }
        let offset = CGAffineTransform(
            translationX: (CGFloat(side) - ink0.extent.width * scale) / 2,
            y: (CGFloat(side) - ink0.extent.height * scale) / 2)
        let canvas = scaled.transformed(by: offset).composited(over: CIImage(color: .black))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))

        var samples = [UInt8](repeating: 0, count: side * side)
        CIContext().render(
            canvas, toBitmap: &samples, rowBytes: side, bounds: canvas.extent, format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray())
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<side * side {
            var alpha = Double(samples[index]) / 255
            if enlarging {
                let t = min(max((alpha - 0.35) / 0.3, 0), 1)
                alpha = t * t * (3 - 2 * t)
            }
            pixels[index * 4] = UInt8((ink.red * alpha * 255).rounded())
            pixels[index * 4 + 1] = UInt8((ink.green * alpha * 255).rounded())
            pixels[index * 4 + 2] = UInt8((ink.blue * alpha * 255).rounded())
            pixels[index * 4 + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: rgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The drawn icon at `pixels` × `pixels`: the spark from `template`, else the ✻ glyph.
    private static func drawnIcon(pixels: Int, template: CGImage?) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGFloat(pixels)
        // macOS icon grid: an 824/1024 rounded square, centred.
        let inset = size * 100 / 1024
        let square = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let radius = square.width * 0.225
        context.addPath(CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(clay)
        context.fillPath()

        let sparkSide = max(1, Int((square.width * 0.56).rounded()))
        let origin = (size - CGFloat(sparkSide)) / 2
        let sparkRect = CGRect(x: origin, y: origin, width: CGFloat(sparkSide), height: CGFloat(sparkSide))
        if let template, let image = spark(from: template, side: sparkSide) {
            context.draw(image, in: sparkRect)
        } else {
            drawGlyph(in: context, square: square)
        }
        return context.makeImage()
    }

    /// Fallback without the Claude app: the ✻ glyph.
    private static func drawGlyph(in context: CGContext, square: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let glyph = NSAttributedString(
            string: "✻",
            attributes: [
                .font: NSFont.systemFont(ofSize: square.width * 0.66, weight: .bold),
                .foregroundColor: NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1),
            ])
        let bounds = glyph.boundingRect(with: square.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        glyph.draw(at: CGPoint(x: square.midX - bounds.width / 2, y: square.midY - bounds.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
