import Foundation

/// What the user chose for an entry. It never carries tool input: the
/// hook builds any `updatedInput` from its own `tool_input` (plus `answers`).
public enum UserDecision: Codable, Equatable, Sendable {
    /// Allow the tool call once.
    case approve
    /// Allow it and add the request's session-only rules (destination "session").
    case approveForSession
    /// Refuse it; Claude gets the fixed deny message.
    case deny
    /// AskUserQuestion: question text -> answer text, for every question.
    case answer([String: String])
    /// ExitPlanMode: accept the plan and leave plan mode.
    case approvePlan
    /// ExitPlanMode: stay in plan mode; the text goes back to Claude as feedback.
    case requestChanges(String)
    /// No decision here: the hook prints nothing and the terminal dialog answers.
    case openInTerminal
}

extension UserDecision {
    /// Builds an `.answer` from the labels picked for each question (including any
    /// "Other" free text). Several labels are joined with ", ", as Claude Code expects
    /// for multi-select. Empty labels are ignored.
    public static func answer(selections: [String: [String]]) -> UserDecision {
        .answer(
            selections.mapValues { labels in
                labels.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
            })
    }
}
