import HookMeUpCore

/// Brings a session's terminal forward ("Open session").
@MainActor
public protocol TerminalActivating {
    /// Activates the terminal app (and, where possible, the tab) that runs the session.
    func activate(_ hint: TerminalHint)
}
