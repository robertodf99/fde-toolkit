/// Where a question entry stands: which question is shown, and the hint after an
/// invalid reply.
public struct QuestionProgress: Equatable, Sendable {
    /// The question being asked, from 0.
    public let step: Int
    /// How many questions the request has.
    public let total: Int
    /// The question being asked.
    public let question: QuestionForm.Question
    /// Shown above the question after a reply that was not understood.
    public let hint: String?

    /// Creates a progress value.
    public init(step: Int, total: Int, question: QuestionForm.Question, hint: String?) {
        self.step = step
        self.total = total
        self.question = question
        self.hint = hint
    }
}
