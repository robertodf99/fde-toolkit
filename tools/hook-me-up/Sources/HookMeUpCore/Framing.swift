import Foundation

/// Length-prefixed JSON frames: 4-byte big-endian payload length, then the payload.
public enum Framing {
    /// The largest payload accepted (1 MiB).
    static let maxFrame = 1 << 20

    /// The frame for `message`; throws `FramingError.oversize` above `maxFrame`.
    public static func encode(_ message: WireMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= maxFrame else { throw FramingError.oversize(payload.count) }
        let length = UInt32(payload.count)
        var frame = Data([
            UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
        ])
        frame.append(payload)
        return frame
    }

    /// Decodes and removes one complete frame from the front of `buffer`. Returns nil
    /// (consuming nothing) while the frame is incomplete; throws on a zero or oversize
    /// length and on a payload that is not a valid message (that frame is consumed).
    public static func decode(_ buffer: inout Data) throws -> WireMessage? {
        guard buffer.count >= 4 else { return nil }
        let start = buffer.startIndex
        let length = buffer[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0 else { throw FramingError.zeroLength }
        guard length <= maxFrame else { throw FramingError.oversize(length) }
        guard buffer.count >= 4 + length else { return nil }
        let payload = Data(buffer[(start + 4)..<(start + 4 + length)])
        buffer.removeSubrange(start..<(start + 4 + length))
        return try JSONDecoder().decode(WireMessage.self, from: payload)
    }
}
