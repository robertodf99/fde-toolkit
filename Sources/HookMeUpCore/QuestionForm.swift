import Foundation

/// The questions of an AskUserQuestion request, parsed from the hook's `tool_input`.
public struct QuestionForm: Equatable, Sendable {
    /// One answer the user can pick.
    public struct Option: Equatable, Sendable {
        /// The answer text sent back to Claude.
        public let label: String
        /// Optional explanation shown with it.
        public let description: String?

        /// Creates an option.
        public init(label: String, description: String?) {
            self.label = label
            self.description = description
        }
    }

    /// One question.
    public struct Question: Equatable, Sendable {
        /// The question; also the key of its answer.
        public let text: String
        /// Short label Claude Code shows as a chip.
        public let header: String?
        /// The answers to pick from (the user can also write their own).
        public let options: [Option]
        /// Whether several options can be picked.
        public let multiSelect: Bool

        /// Creates a question.
        public init(text: String, header: String?, options: [Option], multiSelect: Bool) {
            self.text = text
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    /// The questions, in order.
    public let questions: [Question]

    /// Nil unless `toolInput.questions` holds at least one question with text, and no
    /// two questions share a text (answers are keyed by it).
    public init?(toolInput: JSONValue?) {
        guard let items = toolInput?["questions"]?.arrayValue, !items.isEmpty else { return nil }
        var questions: [Question] = []
        for item in items {
            guard let text = item["question"]?.stringValue, !text.isEmpty else { return nil }
            let options = (item["options"]?.arrayValue ?? []).compactMap { option -> Option? in
                guard let label = option["label"]?.stringValue, !label.isEmpty else { return nil }
                return Option(label: label, description: option["description"]?.stringValue)
            }
            questions.append(
                Question(
                    text: text, header: item["header"]?.stringValue, options: options,
                    multiSelect: item["multiSelect"]?.boolValue ?? false))
        }
        guard Set(questions.map(\.text)).count == questions.count else { return nil }
        self.questions = questions
    }
}
