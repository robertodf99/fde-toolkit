/// What an entry asks the user for.
public enum EntryKind: String, Codable, Sendable {
    /// A tool needs permission.
    case permission
    /// AskUserQuestion.
    case question
    /// ExitPlanMode.
    case plan
    /// Claude waits for a reply (e.g. an MCP form).
    case waiting
    /// The session finished a turn.
    case finished
}
