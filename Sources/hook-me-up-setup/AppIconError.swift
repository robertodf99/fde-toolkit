/// Why the app icon could not be made.
enum AppIconError: Error, CustomStringConvertible {
    /// Drawing the image of this many pixels failed.
    case renderFailed(Int)
    /// The .icns file at this path could not be written.
    case writeFailed(String)

    var description: String {
        switch self {
        case .renderFailed(let pixels): "could not draw the \(pixels)-pixel icon"
        case .writeFailed(let path): "could not write \(path)"
        }
    }
}
