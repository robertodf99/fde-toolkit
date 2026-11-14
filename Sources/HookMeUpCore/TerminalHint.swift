import Foundation

/// How to find the terminal that owns a session: the hook's ancestor PIDs (nearest
/// first) and the controlling tty of the nearest ancestor that has one.
public struct TerminalHint: Codable, Equatable, Sendable {
    /// The hook's ancestor process ids, nearest first.
    public var ancestorPIDs: [Int32]
    /// The controlling terminal, e.g. "ttys003", when an ancestor has one.
    public var tty: String?

    /// Creates a hint.
    public init(ancestorPIDs: [Int32], tty: String?) {
        self.ancestorPIDs = ancestorPIDs
        self.tty = tty
    }
}
