import HookMeUpCore

/// Brings a session forward when its notification is clicked.
@MainActor
public protocol TerminalActivating {
    /// Brings forward the app that runs the session and, where possible, its tab (Terminal,
    /// iTerm2) or the window of its project folder (VS Code, Cursor, Windsurf, Zed).
    func open(_ place: SessionPlace)
}
