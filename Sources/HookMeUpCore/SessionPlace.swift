/// Where a session runs: its terminal and its project folder, used only to bring that
/// session forward on this Mac.
public struct SessionPlace: Equatable, Sendable {
    /// How to find the terminal or editor that runs the session.
    public var terminal: TerminalHint
    /// The session's project folder (git root, else working folder), if known.
    public var folder: String?

    /// Creates a place.
    public init(terminal: TerminalHint, folder: String?) {
        self.terminal = terminal
        self.folder = folder
    }
}
