import Foundation

/// Why a settings file was not read or written. Nothing is written after any of these.
public enum SettingsFileError: Error, Equatable, CustomStringConvertible {
    /// The file at this path is not valid JSON.
    case invalidJSON(String)
    /// The file at this path is JSON but not an object.
    case notAnObject(String)
    /// A number that would lose precision as a Double (beyond ±2^53).
    case unsafeNumber(String)
    /// The file at this path changed after it was read.
    case changedSinceRead(String)
    /// Writing failed (path and reason); the original file is unchanged.
    case writeFailed(String)

    /// A sentence for the installer's output.
    public var description: String {
        switch self {
        case .invalidJSON(let path): "\(path) is not valid JSON"
        case .notAnObject(let path): "\(path) does not contain a JSON object"
        case .unsafeNumber(let number): "the number \(number) would lose precision if rewritten"
        case .changedSinceRead(let path): "\(path) changed while the installer was running; run it again"
        case .writeFailed(let reason): reason
        }
    }
}
