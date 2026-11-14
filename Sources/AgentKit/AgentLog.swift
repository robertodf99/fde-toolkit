import Foundation
import os

/// Agent log: unified logging (subsystem io.github.robertodf99.hook-me-up) plus stderr, which the
/// LaunchAgent sends to ~/Library/Logs/hook-me-up.log. Never logs tool input,
/// commands or messages: only event kinds and short ids.
public enum AgentLog {
    private static let logger = Logger(subsystem: "io.github.robertodf99.hook-me-up", category: "agent")

    /// Logs `message` (event kinds and short ids only, never request content).
    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let stamp = ISO8601DateFormatter.string(
            from: Date(), timeZone: .current,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        FileHandle.standardError.write(Data("\(stamp) hook-me-up: \(message)\n".utf8))
    }

    /// The first eight characters of `id`, enough to follow one request in the log.
    public static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}
