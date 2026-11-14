import Foundation

/// Turns a user decision into the PermissionRequest hook's stdout JSON.
///
/// Returns nil ("print nothing": Claude Code shows its terminal dialog) whenever the
/// decision does not clearly apply: other hook events, no tool name, a decision meant
/// for a different kind of tool, answers that do not match the hook's own questions,
/// empty feedback, and Open in terminal.
public enum DecisionEncoder {
    /// The message Claude receives when the user denies.
    static let denyMessage =
        "User denied this via a notification. Don't retry the same action; ask or try another approach."

    static let askUserQuestion = "AskUserQuestion"
    static let exitPlanMode = "ExitPlanMode"

    /// The hook's stdout for `decision`, built only from the hook's own `input`; nil to
    /// print nothing.
    public static func output(for decision: UserDecision, input: HookInput) -> Data? {
        guard input.hookEventName == "PermissionRequest", let toolName = input.toolName else { return nil }
        // These two tools need updatedInput to work; a plain allow is never sent for them.
        let needsUpdatedInput = toolName == askUserQuestion || toolName == exitPlanMode

        let decisionBody: Decision
        switch decision {
        case .approve:
            guard !needsUpdatedInput else { return nil }
            decisionBody = Decision(behavior: "allow")

        case .approveForSession:
            guard !needsUpdatedInput else { return nil }
            let kept = SessionPermissionFilter.sessionOnly(input.permissionSuggestions)
            decisionBody = Decision(behavior: "allow", updatedPermissions: kept.isEmpty ? nil : kept)

        case .deny:
            decisionBody = Decision(behavior: "deny", message: denyMessage)

        case .answer(let answers):
            guard toolName == askUserQuestion,
                let updated = toolInputWithAnswers(input.toolInput, answers: answers)
            else { return nil }
            decisionBody = Decision(behavior: "allow", updatedInput: updated)

        case .approvePlan:
            guard toolName == exitPlanMode, let toolInput = input.toolInput, toolInput.objectValue != nil else {
                return nil
            }
            decisionBody = Decision(behavior: "allow", updatedInput: toolInput)

        case .requestChanges(let feedback):
            let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard toolName == exitPlanMode, !text.isEmpty else { return nil }
            decisionBody = Decision(behavior: "deny", message: text)

        case .openInTerminal:
            return nil
        }

        return try? decisionBody.outputJSON()
    }

    /// The hook's own tool_input with `answers` set, only when the answers cover exactly
    /// the hook's own question texts, each with a non-blank answer.
    private static func toolInputWithAnswers(_ toolInput: JSONValue?, answers: [String: String]) -> JSONValue? {
        guard var object = toolInput?.objectValue, let questions = object["questions"]?.arrayValue, !questions.isEmpty
        else { return nil }
        var questionTexts = Set<String>()
        for question in questions {
            guard let text = question["question"]?.stringValue else { return nil }
            questionTexts.insert(text)
        }
        // `answers` is keyed by question text: repeated texts cannot be answered apart.
        guard questionTexts.count == questions.count, Set(answers.keys) == questionTexts,
            answers.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }
        object["answers"] = .object(answers.mapValues(JSONValue.string))
        return .object(object)
    }

    private struct Decision {
        var behavior: String
        var updatedInput: JSONValue?
        var updatedPermissions: [PermissionUpdate]?
        var message: String?

        /// JSONEncoder does not keep key order stable, so the envelope keys are written
        /// in a fixed order here; every value is still escaped by JSONEncoder (sorted
        /// keys inside). Compact output is a single line: newlines in strings become \n.
        func outputJSON() throws -> Data {
            var fields = [#""behavior":"# + (try literal(behavior))]
            if let updatedInput { fields.append(#""updatedInput":"# + (try literal(updatedInput))) }
            if let updatedPermissions { fields.append(#""updatedPermissions":"# + (try literal(updatedPermissions))) }
            if let message { fields.append(#""message":"# + (try literal(message))) }
            let decision = "{" + fields.joined(separator: ",") + "}"
            return Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":"#.utf8)
                + Data(decision.utf8) + Data("}}".utf8)
        }

        private func literal<T: Encodable>(_ value: T) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
    }
}
