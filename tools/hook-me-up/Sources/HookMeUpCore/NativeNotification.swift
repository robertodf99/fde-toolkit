import Foundation

/// The native-notification UI as pure data: entry -> notification, response ->
/// outcome. The app turns it into UNUserNotificationCenter calls.
public enum NativeNotification {
    /// Option buttons shown as actions; more options are numbered in the body instead.
    static let maxOptionActions = 4

    /// The action identifiers reported back in responses.
    enum ActionID {
        static let approve = "approve"
        static let approveForSession = "approve-session"
        static let deny = "deny"
        static let approvePlan = "approve-plan"
        static let requestChanges = "request-changes"
        static let reply = "reply"
        static func option(_ index: Int) -> String { "option-\(index)" }
    }

    // MARK: Entry -> notification

    /// The notification for `entry`: title "project · kind", the request in plain
    /// language, and the buttons for its kind. `request` (the live request, if any)
    /// supplies question options, the plan and the session rules; `progress` says which
    /// question is being asked.
    public static func spec(for entry: PendingStore.Entry, request: RequestEnvelope?, progress: QuestionProgress?)
        -> NotificationSpec
    {
        let project = entry.project.name + (entry.client == .codex ? " · Codex" : "")
        let origin: String
        switch entry.summary.origin {
        case .subagent?: origin = " · subagent"
        case .headless?: origin = " · headless"
        case nil: origin = ""
        }
        func make(
            _ kind: String, category: String, body: String, actions: [NotificationActionSpec],
            sound: Bool = true
        ) -> NotificationSpec {
            NotificationSpec(
                identifier: entry.id.uuidString, threadIdentifier: threadIdentifier(for: entry.project),
                categoryIdentifier: category,
                title: "\(project) · \(kind)\(origin)", body: body, actions: actions, playsSound: sound)
        }

        if entry.state == .timedOut {
            return make(
                "Timed out", category: "timed-out", body: "Answer in the terminal: \(entry.summary.title)",
                actions: [], sound: false)
        }

        switch entry.kind {
        case .permission:
            var body = lines(entry.summary.title, entry.summary.description)
            let warnings = entry.summary.tags.map { "⚠︎ \($0.label)" }
            if !warnings.isEmpty { body += "\n" + warnings.joined(separator: "  ") }
            let rules = entry.client == .codex ? [] : sessionRules(request?.sessionPermissions ?? [])
            // Most likely first: macOS shows the first action as a button, the rest under
            // "Options". Clicking the body opens the session.
            var actions = [
                NotificationActionSpec(identifier: ActionID.approve, title: "Approve", requiresAuthentication: true),
                NotificationActionSpec(
                    identifier: ActionID.deny, title: "Deny", style: .destructive, requiresAuthentication: true),
            ]
            if !rules.isEmpty {
                actions.append(
                    NotificationActionSpec(
                        identifier: ActionID.approveForSession,
                        title: "Approve for session: \(rules.joined(separator: ", "))", requiresAuthentication: true))
            }
            // The session button's title names this request's rules, so its category is
            // per entry: macOS keys buttons by category identifier.
            let category = rules.isEmpty ? "permission" : "permission-session-\(entry.id.uuidString)"
            return make(
                "Needs permission", category: category,
                body: body, actions: actions)

        case .question:
            guard let progress else {
                return make("Question", category: "question", body: entry.summary.title, actions: [])
            }
            let kind = progress.total > 1 ? "Question \(progress.step + 1) of \(progress.total)" : "Question"
            let question = progress.question
            var body = progress.hint.map { "⚠︎ \($0)\n" } ?? ""
            var actions: [NotificationActionSpec] = []
            let numbered = question.options.enumerated().map { "\($0.offset + 1). \($0.element.label)" }
            switch replyMode(for: question) {
            case .freeText:
                body += question.text
                actions.append(reply(placeholder: "Your answer"))
            case .numbered where question.multiSelect:
                body += ([question.text + " (select all that apply)"] + numbered + ["Reply with numbers, e.g. 1, 3."])
                    .joined(separator: "\n")
                actions.append(reply(placeholder: "e.g. 1, 3"))
            case .numbered:
                body += ([question.text] + numbered + ["Reply with a number or your own answer."]).joined(
                    separator: "\n")
                actions.append(reply(placeholder: "Number or your own answer"))
            case .buttons:
                body += question.text
                actions = question.options.enumerated().map {
                    NotificationActionSpec(
                        identifier: ActionID.option($0.offset), title: $0.element.label, requiresAuthentication: true)
                }
                actions.append(reply(placeholder: "Your own answer"))
            }
            return make(kind, category: questionCategory(entry.id, step: progress.step), body: body, actions: actions)

        case .plan:
            let plan = request?.input["plan"]?.stringValue ?? ""
            let body = ([entry.summary.description] + planPreview(plan)).filter { !$0.isEmpty }.joined(separator: "\n")
            return make(
                "Plan to approve", category: "plan", body: body.isEmpty ? entry.summary.title : body,
                actions: [
                    NotificationActionSpec(
                        identifier: ActionID.approvePlan, title: "Approve plan", requiresAuthentication: true),
                    NotificationActionSpec(
                        identifier: ActionID.requestChanges, title: "Request changes…",
                        textInput: .init(buttonTitle: "Send", placeholder: "What should change?"),
                        requiresAuthentication: true),
                ])

        case .finished:
            let gist = entry.summary.description.isEmpty ? entry.summary.title : entry.summary.description
            return make("Finished", category: "finished", body: gist, actions: [])

        case .waiting:
            return make("Waiting for your reply", category: "waiting", body: entry.summary.description, actions: [])
        }
    }

    /// Groups a project's notifications: its name plus a short hash of its repository's
    /// shared git folder (so all working trees of one repository share a group, and two
    /// repositories with the same name stay apart), else of its working folder.
    static func threadIdentifier(for project: ProjectInfo) -> String {
        guard let folder = project.gitCommonDir ?? project.gitRoot ?? project.folder else { return project.name }
        return "\(project.name)-\(shortHash(folder))"
    }

    /// FNV-1a (32 bits) as 8 hex digits: stable across runs, unlike `hashValue`.
    static func shortHash(_ text: String) -> String {
        var hash: UInt32 = 0x811c_9dc5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }

    /// The category of question `step` of entry `id` (its buttons are that question's options).
    static func questionCategory(_ id: UUID, step: Int) -> String {
        "question-\(id.uuidString)-\(step)"
    }

    // MARK: Response -> outcome

    /// What to do about `response` to the notification of `entry`, posted with
    /// `categoryIdentifier`. An action counts only if the notification the entry shows
    /// now (`spec(for:request:progress:)`) has that category and that button; anything
    /// else (an earlier question, a stale or forged category) is ignored.
    public static func outcome(
        of response: NotificationResponse, categoryIdentifier: String,
        entry: PendingStore.Entry, request: RequestEnvelope?, progress: QuestionProgress?
    ) -> NotificationOutcome {
        let actionID: String
        let isText: Bool
        switch response {
        case .dismissed:
            return .ignore
        case .defaultClick:
            return .openSession  // clicking the body opens the session, for every kind
        case .action(let id):
            (actionID, isText) = (id, false)
        case .text(let id, _):
            (actionID, isText) = (id, true)
        }
        let shown = spec(for: entry, request: request, progress: progress)
        guard categoryIdentifier == shown.categoryIdentifier,
            let action = shown.actions.first(where: { $0.identifier == actionID }),
            (action.textInput != nil) == isText
        else { return .ignore }

        switch entry.kind {
        case .permission:
            switch response {
            case .action(ActionID.approve): return .decide(.approve)
            case .action(ActionID.approveForSession): return .decide(.approveForSession)
            case .action(ActionID.deny): return .decide(.deny)
            default: return .ignore
            }

        case .plan:
            switch response {
            case .action(ActionID.approvePlan):
                return .decide(.approvePlan)
            case .text(ActionID.requestChanges, let text):
                let feedback = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return feedback.isEmpty ? .repost : .decide(.requestChanges(feedback))
            default:
                return .ignore
            }

        case .question:
            guard let progress else { return .ignore }
            let question = progress.question
            switch response {
            case .action(let id) where id.hasPrefix("option-"):
                guard let index = Int(id.dropFirst("option-".count)), question.options.indices.contains(index),
                    replyMode(for: question) == .buttons
                else { return .ignore }
                return .answer(step: progress.step, labels: [question.options[index].label])
            case .text(ActionID.reply, let text):
                switch parseReply(text, for: question) {
                case .labels(let labels): return .answer(step: progress.step, labels: labels)
                case .invalid(let hint): return .invalidReply(step: progress.step, hint: hint)
                }
            default:
                return .ignore
            }

        case .finished, .waiting:
            return .ignore
        }
    }

    /// A text reply, understood: the picked labels (or free text), or a hint to show.
    enum ReplyParse: Equatable, Sendable {
        case labels([String])
        case invalid(String)
    }

    /// Single choice: an option number, an option label, or free text ("Other").
    /// Multi-select: option numbers and/or labels separated by commas or spaces.
    static func parseReply(_ text: String, for question: QuestionForm.Question) -> ReplyParse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = question.options.map(\.label)
        func label(matching token: String) -> String? {
            labels.first { $0.caseInsensitiveCompare(token) == .orderedSame }
        }
        func label(numbered token: String) -> String? {
            guard !token.isEmpty, token.allSatisfy(\.isASCII), token.allSatisfy(\.isNumber), let number = Int(token),
                labels.indices.contains(number - 1)
            else { return nil }
            return labels[number - 1]
        }

        switch replyMode(for: question) {
        case .freeText:
            return trimmed.isEmpty ? .invalid("Reply with your answer") : .labels([trimmed])

        case .buttons:
            // The options are buttons: the reply is the user's own answer, unless it is
            // exactly one of the labels. A number is never read as an index here.
            guard !trimmed.isEmpty else { return .invalid("Pick an option or reply with your own answer") }
            return .labels([label(matching: trimmed) ?? trimmed])

        case .numbered where !question.multiSelect:
            let hint = "Reply with 1–\(labels.count) or your own answer"
            guard !trimmed.isEmpty else { return .invalid(hint) }
            // A number from 1 to the option count is the number shown in the body, even if
            // a label is that number too; only other text (or a larger number) can be a label.
            // "4." is written like the list itself.
            let number = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
            if let shown = label(numbered: number) { return .labels([shown]) }
            if let match = label(matching: trimmed) { return .labels([match]) }
            if !number.isEmpty, number.allSatisfy(\.isNumber) { return .invalid(hint) }  // "6", "6." out of range
            return .labels([trimmed])  // "Other": the user's own answer

        case .numbered:
            let hint = "Reply with option numbers, e.g. 1, 3"
            var tokens: [String] = []
            for part in trimmed.split(separator: ",") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                if piece.allSatisfy({ $0.isNumber || $0 == " " }) {
                    tokens += piece.split(separator: " ").map(String.init)
                } else {
                    tokens.append(piece)
                }
            }
            tokens = tokens.filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return .invalid(hint) }
            let shown = tokens.compactMap(label(numbered:))
            if shown.count == tokens.count {  // only numbers from the list: they are the indices
                return .labels(labels.filter(shown.contains))  // option order
            }
            if let match = label(matching: trimmed) { return .labels([match]) }  // a label may contain commas
            // A number beyond the count can only be a label. Then a number in range whose
            // index and label name different options ("3, 8" with 1, 3, 4, 8) is ambiguous.
            let numeric = tokens.filter { $0.allSatisfy(\.isNumber) }
            let labelOnly = numeric.contains { label(numbered: $0) == nil && label(matching: $0) != nil }
            let twoMeanings = numeric.contains { token in
                guard let shown = label(numbered: token), let named = label(matching: token) else { return false }
                return shown != named
            }
            if labelOnly, twoMeanings { return .invalid(hint) }
            // Each option may be named by one token only (the same number twice is fine):
            // "4, 8" with labels 1, 2, 4, 8 reaches "8" by index and by label, so ask again.
            var pickedBy: [String: String] = [:]
            for token in tokens {
                guard let match = label(numbered: token) ?? label(matching: token) else { return .invalid(hint) }
                let key = Int(token).map(String.init) ?? token.lowercased()
                if let earlier = pickedBy[match], earlier != key { return .invalid(hint) }
                pickedBy[match] = key
            }
            return .labels(labels.filter { pickedBy[$0] != nil })  // option order
        }
    }

    /// How a question is answered from the notification.
    enum ReplyMode: Equatable {
        /// No options: "Reply…" only.
        case freeText
        /// Up to four options, single choice: one button each, plus "Reply…".
        case buttons
        /// Multi-select or more than four options: numbered in the body, answered by "Reply…".
        case numbered
    }

    static func replyMode(for question: QuestionForm.Question) -> ReplyMode {
        if question.options.isEmpty { return .freeText }
        return question.multiSelect || question.options.count > maxOptionActions ? .numbered : .buttons
    }

    // MARK: Test notification

    /// The identifier of the installer's test notification; it is never an entry's.
    public static let testIdentifier = "hook-me-up-test"

    /// The installer's test notification (`hook-me-up-setup notifications --test`): no
    /// category and no buttons, so nothing can be answered from it. With a style other
    /// than Alerts it says to change it.
    public static func testSpec(alertStyle: NotificationAuthorization.AlertStyle) -> NotificationSpec {
        NotificationSpec(
            identifier: testIdentifier, threadIdentifier: testIdentifier, categoryIdentifier: "",
            title: "Hook Me Up",
            body: alertStyle == .alert
                ? "Notifications work. Claude Code's requests will show up like this."
                : "Notifications work. Set the style to Alerts so requests stay on screen.",
            actions: [])
    }

    // MARK: Store -> post / remove

    /// Post what is new or changed (e.g. the next question, a hint); remove what is gone
    /// (answered, the hook interrupted or its process gone, the session finished its turn,
    /// cleared, session gone).
    public static func changes(before: [NotificationSpec], after: [NotificationSpec]) -> NotificationChanges {
        let old = Dictionary(before.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(after.map(\.identifier))
        return NotificationChanges(
            post: after.filter { old[$0.identifier] != $0 },
            remove: before.map(\.identifier).filter { !kept.contains($0) })
    }

    // MARK: Helpers

    private static func reply(placeholder: String) -> NotificationActionSpec {
        NotificationActionSpec(
            identifier: ActionID.reply, title: "Reply…",
            textInput: .init(buttonTitle: "Send", placeholder: placeholder), requiresAuthentication: true)
    }

    private static func lines(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// "Bash(npm test:*)" / "folder ~/x" for what "allow for session" would add.
    static func sessionRules(_ updates: [PermissionUpdate]) -> [String] {
        updates.flatMap { update -> [String] in
            switch update.type {
            case "addRules":
                return (update.rules ?? []).map { rule in
                    rule.ruleContent.map { "\(rule.toolName)(\($0))" } ?? rule.toolName
                }
            case "addDirectories":
                return (update.directories ?? []).map { "folder \($0)" }
            default:
                return []
            }
        }
    }

    /// The first four lines of the plan after its title, markdown markers removed.
    static func planPreview(_ plan: String) -> [String] {
        let lines = plan.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst()  // the title is already in the body
            .map { Summarizer.cleanInline(String($0.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)) }
            .prefix(4)
            .map { $0 }
    }
}
