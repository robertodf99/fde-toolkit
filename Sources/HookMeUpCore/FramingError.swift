/// Why a wire frame was refused.
public enum FramingError: Error, Equatable, CustomStringConvertible {
    /// A frame announced an empty payload.
    case zeroLength
    /// A frame (or a message to send) is larger than `Framing.maxFrame`.
    case oversize(Int)

    /// A sentence for the log.
    public var description: String {
        switch self {
        case .zeroLength: "empty frame"
        case .oversize(let bytes): "frame of \(bytes) bytes is over the limit"
        }
    }
}
