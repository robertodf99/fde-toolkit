import Foundation

/// How to find the terminal that owns a session: the session's process and its ancestors
/// (nearest first) and the controlling tty of the nearest one that has one.
public struct TerminalHint: Codable, Equatable, Sendable {
    /// The hook's ancestor process ids, nearest first, from the session's process (Claude
    /// Code) up: a shell that only ran the hook is left out.
    public var ancestorPIDs: [Int32]
    /// The controlling terminal, e.g. "ttys003", when an ancestor has one.
    public var tty: String?

    /// Creates a hint.
    public init(ancestorPIDs: [Int32], tty: String?) {
        self.ancestorPIDs = ancestorPIDs
        self.tty = tty
    }
}
