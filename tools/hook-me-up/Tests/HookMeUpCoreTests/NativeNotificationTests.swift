import Foundation
import Testing

@testable import HookMeUpCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let project = ProjectInfo(name: "demo-app", gitRoot: nil, branch: nil, worktree: nil)

private let fixedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

private func entry(
    _ kind: EntryKind, title: String, description: String, tags: [EffectTag] = [],
    state: PendingStore.Entry.State = .pending, id: UUID = fixedID
) -> PendingStore.Entry {
    PendingStore.Entry(
        id: id, sessionID: "s1", kind: kind,
        summary: RequestSummary(
            kind: kind, title: title, description: description, tags: tags, origin: nil),
        project: project, terminal: TerminalHint(ancestorPIDs: [], tty: nil), state: state)
}

private func request(
    _ entry: PendingStore.Entry, input: JSONValue = .object([:]),
    session: [PermissionUpdate] = []
) -> RequestEnvelope {
    RequestEnvelope(
        id: entry.id, sessionID: entry.sessionID, project: entry.project, summary: entry.summary,
        input: input, terminal: entry.terminal, sessionPermissions: session)
}

private func question(_ text: String, _ labels: [String], multi: Bool = false) -> QuestionForm.Question {
    QuestionForm.Question(
        text: text, header: nil, options: labels.map { .init(label: $0, description: nil) }, multiSelect: multi)
}

private let colours = question("Which colour?", ["Blue", "Orange"])
private let many = question("Which day?", ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
private let likes = question("Which do you like?", ["Blue", "Orange", "Green", "Purple"], multi: true)

@Suite struct NativeNotificationSpecTests {
    @Test func permissionHasApproveThenDeny() {
        let e = entry(
            .permission, title: "Push to a remote repository", description: "Uploads 3 commits",
            tags: [.network, .gitPush])
        let spec = NativeNotification.spec(for: e, request: request(e), progress: nil)
        #expect(spec.identifier == e.id.uuidString)
        #expect(spec.threadIdentifier == "demo-app")  // no folder known: the name alone
        #expect(spec.title == "demo-app · Needs permission")
        #expect(
            spec.body == "Push to a remote repository\nUploads 3 commits\n⚠︎ Leaves your machine  ⚠︎ Pushes to a remote")
        #expect(spec.categoryIdentifier == "permission")
        #expect(
            spec.actions == [
                .init(identifier: "approve", title: "Approve", requiresAuthentication: true),
                .init(identifier: "deny", title: "Deny", style: .destructive, requiresAuthentication: true),
            ])
        #expect(spec.playsSound)
    }

    @Test func approveForSessionOnlyWhenASessionRuleSurvives() {
        let e = entry(.permission, title: "Run a command", description: "ls")
        let rule = PermissionUpdate(
            type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "ls")],
            behavior: "allow", destination: "session")
        let spec = NativeNotification.spec(for: e, request: request(e, session: [rule]), progress: nil)
        #expect(spec.categoryIdentifier == "permission-session-\(e.id.uuidString)")
        #expect(spec.actions.map(\.identifier) == ["approve", "deny", "approve-session"])
        #expect(spec.actions[2].title == "Approve for session: Bash(ls)")
    }

    /// Approving from the lock screen needs an unlock: every button that answers Claude
    /// requires authentication (every action does: opening the session is the body click).
    @Test func everyDecidingActionRequiresUnlocking() {
        let rule = PermissionUpdate(
            type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "ls")], behavior: "allow",
            destination: "session")
        let permission = entry(.permission, title: "Run a command", description: "ls")
        let question = entry(.question, title: "Which colour?", description: "")
        let plan = entry(.plan, title: "Plan", description: "")
        let specs = [
            NativeNotification.spec(for: permission, request: request(permission, session: [rule]), progress: nil),
            NativeNotification.spec(
                for: question, request: request(question),
                progress: QuestionProgress(step: 0, total: 1, question: colours, hint: nil)),
            NativeNotification.spec(
                for: question, request: request(question),
                progress: QuestionProgress(step: 0, total: 1, question: likes, hint: nil)),
            NativeNotification.spec(for: plan, request: request(plan), progress: nil),
        ]
        let actions = specs.flatMap(\.actions)
        #expect(
            Set(actions.map(\.identifier)).isSuperset(of: [
                "approve", "approve-session", "deny", "option-0", "reply", "approve-plan", "request-changes",
            ]))
        for action in actions {
            #expect(action.requiresAuthentication, "\(action.identifier)")
        }
    }

    /// Notifications group by thread: one per repository (all its working trees), and two
    /// repositories with the same name stay apart.
    @Test func threadIsTheProjectNamePlusAShortHashOfItsFolder() {
        func thread(_ project: ProjectInfo) -> String {
            var e = entry(.permission, title: "t", description: "d")
            e.project = project
            return NativeNotification.spec(for: e, request: nil, progress: nil).threadIdentifier
        }
        let work = ProjectInfo(name: "api", gitRoot: "/home/dev/work/api", branch: nil, worktree: nil)
        let personal = ProjectInfo(name: "api", gitRoot: "/home/dev/personal/api", branch: "main", worktree: nil)
        let plain = ProjectInfo(name: "api", gitRoot: nil, branch: nil, worktree: nil, folder: "/home/dev/tmp/api")
        #expect(thread(work) != thread(personal))
        #expect(thread(plain) != thread(work))
        #expect(thread(work) == thread(work))
        // A checkout and its linked worktree share the repository's git folder: one group.
        let checkout = ProjectInfo(
            name: "api", gitRoot: "/home/dev/work/api", branch: "main", worktree: nil,
            gitCommonDir: "/home/dev/work/api/.git")
        let linked = ProjectInfo(
            name: "api", gitRoot: "/home/dev/work/api-feature", branch: "feature", worktree: "api-feature",
            gitCommonDir: "/home/dev/work/api/.git")
        #expect(thread(checkout) == thread(linked))
        #expect(thread(checkout) == "api-" + NativeNotification.shortHash("/home/dev/work/api/.git"))
        #expect(thread(work).hasPrefix("api-"))
        #expect(thread(work).count == "api-".count + 8)
        #expect(thread(work) == NativeNotification.threadIdentifier(for: work))
        #expect(
            NativeNotification.threadIdentifier(for: work) == "api-"
                + "\(NativeNotification.shortHash("/home/dev/work/api"))")
        // FNV-1a: stable across runs (unlike hashValue).
        #expect(NativeNotification.shortHash("") == "811c9dc5")
        #expect(NativeNotification.shortHash("a") == "e40c292c")
    }

    /// macOS keys action buttons by category: a category shared by two notifications
    /// must have the same buttons, or one request's rule could label another's button.
    @Test func aCategoryIdentifierAlwaysMeansTheSameActions() {
        func sessionRule(_ content: String) -> [PermissionUpdate] {
            [
                PermissionUpdate(
                    type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: content)],
                    behavior: "allow", destination: "session")
            ]
        }
        var specs: [NotificationSpec] = []
        for content in ["ls", "rm -rf build", "npm test:*"] {
            let e = entry(.permission, title: "Run a command", description: content, id: UUID())
            specs.append(
                NativeNotification.spec(for: e, request: request(e, session: sessionRule(content)), progress: nil))
            let plain = entry(.permission, title: "Run a command", description: content, id: UUID())
            specs.append(NativeNotification.spec(for: plain, request: request(plain), progress: nil))
        }
        for questionForm in [colours, many, likes] {
            let e = entry(.question, title: questionForm.text, description: "", id: UUID())
            specs.append(
                NativeNotification.spec(
                    for: e, request: request(e),
                    progress: QuestionProgress(step: 0, total: 1, question: questionForm, hint: nil)))
        }
        for kind in [EntryKind.plan, .finished, .waiting] {
            let e = entry(kind, title: "t", description: "d", id: UUID())
            specs.append(NativeNotification.spec(for: e, request: request(e), progress: nil))
        }
        let timedOut = entry(.permission, title: "t", description: "d", state: .timedOut, id: UUID())
        specs.append(NativeNotification.spec(for: timedOut, request: nil, progress: nil))

        let byCategory = Dictionary(grouping: specs, by: \.categoryIdentifier)
        for (category, group) in byCategory {
            #expect(Set(group.map { $0.actions.map(\.title) }).count == 1, "\(category) has different buttons")
        }
        #expect(byCategory.keys.filter { $0.hasPrefix("permission-session-") }.count == 3)
    }

    @Test func singleChoiceQuestionHasOneActionPerOptionAndReply() {
        let e = entry(.question, title: "Which colour?", description: "Claude is asking you 2 questions")
        let spec = NativeNotification.spec(
            for: e, request: request(e),
            progress: QuestionProgress(step: 0, total: 2, question: colours, hint: nil))
        #expect(spec.title == "demo-app · Question 1 of 2")
        #expect(spec.body == "Which colour?")
        #expect(spec.categoryIdentifier == "question-\(e.id.uuidString)-0")
        #expect(
            spec.actions == [
                .init(identifier: "option-0", title: "Blue", requiresAuthentication: true),
                .init(identifier: "option-1", title: "Orange", requiresAuthentication: true),
                .init(
                    identifier: "reply", title: "Reply…",
                    textInput: .init(buttonTitle: "Send", placeholder: "Your own answer"),
                    requiresAuthentication: true),
            ])
    }

    @Test func singleChoiceWithManyOptionsNumbersThemInTheBody() {
        let e = entry(.question, title: "Which day?", description: "")
        let spec = NativeNotification.spec(
            for: e, request: request(e),
            progress: QuestionProgress(step: 0, total: 1, question: many, hint: nil))
        #expect(spec.title == "demo-app · Question")
        #expect(
            spec.body
                == "Which day?\n1. Mon\n2. Tue\n3. Wed\n4. Thu\n5. Fri\n6. Sat\nReply with a number or your own answer."
        )
        #expect(spec.actions.map(\.identifier) == ["reply"])
        #expect(spec.actions[0].textInput?.placeholder == "Number or your own answer")
    }

    @Test func aQuestionWithoutOptionsOnlyTakesAReply() {
        let e = entry(.question, title: "Anything else?", description: "")
        let openQuestion = question("Anything else?", [], multi: true)
        let spec = NativeNotification.spec(
            for: e, request: request(e),
            progress: QuestionProgress(step: 0, total: 1, question: openQuestion, hint: nil))
        #expect(spec.body == "Anything else?")
        #expect(spec.actions.map(\.identifier) == ["reply"])
        #expect(spec.actions.first?.textInput?.placeholder == "Your answer")
    }

    @Test func multiSelectNumbersOptionsAndShowsTheHint() {
        let e = entry(.question, title: "Which do you like?", description: "")
        let spec = NativeNotification.spec(
            for: e, request: request(e),
            progress: QuestionProgress(step: 1, total: 2, question: likes, hint: "Reply with option numbers, e.g. 1, 3")
        )
        #expect(spec.title == "demo-app · Question 2 of 2")
        #expect(
            spec.body
                == "⚠︎ Reply with option numbers, e.g. 1, 3\nWhich do you like? (select all that apply)\n1. Blue\n2. Orange\n3. Green\n4. Purple\nReply with numbers, e.g. 1, 3."
        )
        #expect(
            spec.actions == [
                .init(
                    identifier: "reply", title: "Reply…",
                    textInput: .init(buttonTitle: "Send", placeholder: "e.g. 1, 3"),
                    requiresAuthentication: true)
            ])
    }

    @Test func planHasApproveThenRequestChanges() {
        let e = entry(.plan, title: "Review Claude's plan", description: "Plan: create hello.txt")
        let plan =
            "# Plan: create hello.txt\n\n## Steps\n1. Create the file\n2. Write hello\n3. Verify\n4. Commit\n5. Push\n"
        let spec = NativeNotification.spec(
            for: e, request: request(e, input: .object(["plan": .string(plan)])), progress: nil)
        #expect(spec.title == "demo-app · Plan to approve")
        #expect(spec.body == "Plan: create hello.txt\nSteps\n1. Create the file\n2. Write hello\n3. Verify")
        #expect(
            spec.actions == [
                .init(identifier: "approve-plan", title: "Approve plan", requiresAuthentication: true),
                .init(
                    identifier: "request-changes", title: "Request changes…",
                    textInput: .init(buttonTitle: "Send", placeholder: "What should change?"),
                    requiresAuthentication: true),
            ])
    }

    @Test func finishedAndWaitingHaveNoActions() {
        let finished = NativeNotification.spec(
            for: entry(.finished, title: "Finished", description: "All tests pass."),
            request: nil, progress: nil)
        #expect(finished.title == "demo-app · Finished")
        #expect(finished.body == "All tests pass.")
        #expect(finished.categoryIdentifier == "finished")
        #expect(finished.actions.isEmpty)
        let waiting = NativeNotification.spec(
            for: entry(.waiting, title: "Waiting for your reply", description: "A form is open"),
            request: nil, progress: nil)
        #expect(waiting.title == "demo-app · Waiting for your reply")
        #expect(waiting.body == "A form is open")
        #expect(waiting.actions.isEmpty)
    }

    @Test func timedOutHasNoActions() {
        let e = entry(.permission, title: "Run a command", description: "ls", state: .timedOut)
        let spec = NativeNotification.spec(for: e, request: nil, progress: nil)
        #expect(spec.title == "demo-app · Timed out")
        #expect(spec.body == "Answer in the terminal: Run a command")
        #expect(spec.actions.isEmpty)  // clicking it opens the session
        #expect(!spec.playsSound)
    }
}

@Suite struct NativeNotificationResponseTests {
    @Test func permissionActions() {
        let e = entry(.permission, title: "t", description: "d")
        func outcome(_ r: NotificationResponse) -> NotificationOutcome {
            NativeNotification.outcome(
                of: r, categoryIdentifier: "permission", entry: e, request: request(e), progress: nil)
        }
        #expect(outcome(.action("approve")) == .decide(.approve))
        #expect(outcome(.action("deny")) == .decide(.deny))
        // Not one of this notification's buttons: no session rule was offered.
        #expect(outcome(.action("approve-session")) == .ignore)
        #expect(outcome(.text(action: "approve", text: "x")) == .ignore)
        #expect(outcome(.action("open")) == .ignore)  // no such button any more
        #expect(outcome(.defaultClick) == .openSession)  // clicking the body opens the session
        #expect(outcome(.dismissed) == .ignore)
        #expect(outcome(.action("something-else")) == .ignore)
    }

    /// The body click opens the session for every kind, in every state, and never decides.
    @Test func theBodyClickAlwaysOpensTheSession() {
        let kinds: [EntryKind] = [.permission, .question, .plan, .finished, .waiting]
        for kind in kinds {
            for state in [PendingStore.Entry.State.pending, .timedOut] {
                let e = entry(kind, title: "t", description: "d", state: state)
                let shown = NativeNotification.spec(for: e, request: request(e), progress: nil)
                #expect(
                    NativeNotification.outcome(
                        of: .defaultClick, categoryIdentifier: shown.categoryIdentifier, entry: e, request: request(e),
                        progress: nil) == .openSession, "\(kind) \(state)")
                #expect(!shown.actions.contains { $0.identifier == "open" }, "\(kind) \(state)")
            }
        }
    }

    @Test func approveForSessionCountsOnlyUnderItsOwnCategory() {
        let e = entry(.permission, title: "Run a command", description: "ls")
        let rule = PermissionUpdate(
            type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "ls")], behavior: "allow",
            destination: "session")
        let live = request(e, session: [rule])
        func outcome(_ r: NotificationResponse, _ category: String) -> NotificationOutcome {
            NativeNotification.outcome(of: r, categoryIdentifier: category, entry: e, request: live, progress: nil)
        }
        let own = "permission-session-\(e.id.uuidString)"
        #expect(outcome(.action("approve-session"), own) == .decide(.approveForSession))
        #expect(outcome(.action("approve"), own) == .decide(.approve))
        #expect(outcome(.action("approve-session"), "permission") == .ignore)
        #expect(outcome(.action("approve"), "permission") == .ignore)
        #expect(outcome(.action("approve"), "plan") == .ignore)
        #expect(outcome(.defaultClick, "permission") == .openSession)  // the body always opens the session
    }

    @Test func actionsOfAnotherKindAreIgnored() {
        let plan = entry(.plan, title: "t", description: "d")
        #expect(
            NativeNotification.outcome(
                of: .action("approve"), categoryIdentifier: "plan", entry: plan, request: request(plan), progress: nil)
                == .ignore)
        let timedOut = entry(.permission, title: "t", description: "d", state: .timedOut)
        #expect(
            NativeNotification.outcome(
                of: .action("approve"), categoryIdentifier: "timed-out", entry: timedOut, request: nil, progress: nil)
                == .ignore)
        #expect(
            NativeNotification.outcome(
                of: .defaultClick, categoryIdentifier: "timed-out", entry: timedOut, request: nil, progress: nil)
                == .openSession)
    }

    @Test func planActions() {
        let e = entry(.plan, title: "t", description: "d")
        func outcome(_ r: NotificationResponse) -> NotificationOutcome {
            NativeNotification.outcome(of: r, categoryIdentifier: "plan", entry: e, request: request(e), progress: nil)
        }
        #expect(outcome(.action("approve-plan")) == .decide(.approvePlan))
        #expect(
            outcome(.text(action: "request-changes", text: "  Add tests  ")) == .decide(.requestChanges("Add tests")))
        #expect(outcome(.text(action: "request-changes", text: "   ")) == .repost)  // empty: keep it answerable
        #expect(outcome(.defaultClick) == .openSession)
    }

    @Test func questionOptionsRepliesAndStaleSteps() {
        let e = entry(.question, title: "Which colour?", description: "")
        let progress = QuestionProgress(step: 0, total: 2, question: colours, hint: nil)
        let category = "question-\(e.id.uuidString)-0"
        func outcome(_ r: NotificationResponse, _ category: String = category) -> NotificationOutcome {
            NativeNotification.outcome(
                of: r, categoryIdentifier: category, entry: e, request: request(e), progress: progress)
        }
        #expect(outcome(.action("option-1")) == .answer(step: 0, labels: ["Orange"]))
        #expect(outcome(.text(action: "reply", text: "Teal")) == .answer(step: 0, labels: ["Teal"]))  // "Other"
        #expect(outcome(.text(action: "reply", text: "9")) == .answer(step: 0, labels: ["9"]))  // free text
        #expect(
            outcome(.text(action: "reply", text: "  "))
                == .invalidReply(step: 0, hint: "Pick an option or reply with your own answer"))
        // An older step's notification.
        #expect(outcome(.action("option-0"), "question-\(e.id.uuidString)-1") == .ignore)
        #expect(outcome(.action("option-7")) == .ignore)
        #expect(outcome(.defaultClick) == .openSession)
    }

    /// Options shown as buttons: "Reply…" is the user's own answer. Only the whole text
    /// matching a label (any case) picks that option; a number is never an index.
    @Test(arguments: [
        ("orange", ["Orange"]), (" BLUE ", ["Blue"]), ("Teal, please", ["Teal, please"]), ("2", ["2"]),
        ("1", ["1"]),
    ])
    func buttonQuestionRepliesAreFreeTextUnlessTheyMatchALabel(_ text: String, _ expected: [String]) {
        #expect(NativeNotification.parseReply(text, for: colours) == .labels(expected))
    }

    @Test func numericLabelsShownAsButtonsAreNeverPickedByIndex() {
        let sizes = question("Which size?", ["3", "5"])
        #expect(NativeNotification.parseReply("1", for: sizes) == .labels(["1"]))
        #expect(NativeNotification.parseReply("5", for: sizes) == .labels(["5"]))
        let yesNo = question("Proceed?", ["Yes", "No"])
        #expect(NativeNotification.parseReply("1", for: yesNo) == .labels(["1"]))
        #expect(NativeNotification.parseReply("no", for: yesNo) == .labels(["No"]))
    }

    @Test(arguments: ["", "   "])
    func emptyRepliesToButtonQuestionsAskAgain(_ text: String) {
        #expect(
            NativeNotification.parseReply(text, for: colours)
                == .invalid("Pick an option or reply with your own answer"))
    }

    @Test func questionsWithoutOptionsTakeAnyText() {
        let open = question("What should the file be called?", [])
        #expect(NativeNotification.parseReply("42", for: open) == .labels(["42"]))
        #expect(NativeNotification.parseReply(" notes.md ", for: open) == .labels(["notes.md"]))
        #expect(NativeNotification.parseReply("  ", for: open) == .invalid("Reply with your answer"))
        let openMulti = question("Anything else?", [], multi: true)
        #expect(NativeNotification.parseReply("1, 3", for: openMulti) == .labels(["1, 3"]))
    }

    /// More than four options are numbered in the body: a label still wins, then a number.
    @Test(arguments: [
        ("2", ["Tue"]), ("fri", ["Fri"]), ("Sunday", ["Sunday"]),
    ])
    func numberedSingleChoiceReplies(_ text: String, _ expected: [String]) {
        #expect(NativeNotification.parseReply(text, for: many) == .labels(expected))
    }

    @Test(arguments: ["", "0", "7", "12"])
    func invalidNumberedSingleChoiceReplies(_ text: String) {
        #expect(NativeNotification.parseReply(text, for: many) == .invalid("Reply with 1–6 or your own answer"))
    }

    /// When the options are numbered, a number from 1 to the option count is always the
    /// number shown in the body, even if some label is that number too.
    @Test func anInRangeNumberIsAlwaysTheShownIndexWhenNumbered() {
        let sizes = question("Which size?", ["1", "2", "4", "8", "16"])
        #expect(NativeNotification.parseReply("4", for: sizes) == .labels(["8"]))
        #expect(NativeNotification.parseReply("3", for: sizes) == .labels(["4"]))
        #expect(NativeNotification.parseReply("5", for: sizes) == .labels(["16"]))
        let multiSizes = question("Which sizes?", ["1", "2", "4", "8"], multi: true)
        #expect(NativeNotification.parseReply("3, 4", for: multiSizes) == .labels(["4", "8"]))
        #expect(NativeNotification.parseReply("4", for: multiSizes) == .labels(["8"]))
    }

    /// One option reached twice through different tokens (an index and a label) is
    /// ambiguous: ask again rather than guess. The same number twice is fine.
    @Test func anOptionReachedByIndexAndByLabelIsAmbiguous() {
        let sizes = question("Which sizes?", ["1", "2", "4", "8"], multi: true)
        #expect(NativeNotification.parseReply("4, 8", for: sizes) == .invalid("Reply with option numbers, e.g. 1, 3"))
        #expect(NativeNotification.parseReply("1, 1", for: sizes) == .labels(["1"]))
        #expect(NativeNotification.parseReply("01, 1", for: sizes) == .labels(["1"]))
        let amounts = question("Which amounts?", ["10", "20", "30", "40"], multi: true)
        #expect(
            NativeNotification.parseReply("2, 20", for: amounts) == .invalid("Reply with option numbers, e.g. 1, 3"))
    }

    /// A number beyond the option count can only be a label; when another number in the
    /// same reply would mean one option as an index and another as a label, ask again.
    @Test(arguments: ["3, 8", "8, 3", "3 8"])
    func aLabelOnlyNumberMakesAnotherNumbersMeaningAmbiguous(_ reply: String) {
        let values = question("Which values?", ["1", "3", "4", "8"], multi: true)
        #expect(NativeNotification.parseReply(reply, for: values) == .invalid("Reply with option numbers, e.g. 1, 3"))
    }

    @Test func numbersWhoseIndexAndLabelAgreeStayValid() {
        let values = question("Which values?", ["1", "3", "4", "8"], multi: true)
        #expect(NativeNotification.parseReply("1, 8", for: values) == .labels(["1", "8"]))
        #expect(NativeNotification.parseReply("2, 4", for: values) == .labels(["3", "8"]))
        #expect(NativeNotification.parseReply("8", for: values) == .labels(["8"]))
    }

    /// "4." is how a numbered list writes 4.
    @Test func aNumberWithATrailingDotIsAnIndexWhenNumbered() {
        #expect(NativeNotification.parseReply("4.", for: many) == .labels(["Thu"]))
        let sizes = question("Which size?", ["1", "2", "4", "8", "16"])
        #expect(NativeNotification.parseReply("4.", for: sizes) == .labels(["8"]))
        #expect(NativeNotification.parseReply(" 2. ", for: sizes) == .labels(["2"]))
        // Out of range with or without the dot: the hint.
        #expect(NativeNotification.parseReply("6.", for: sizes) == .invalid("Reply with 1–5 or your own answer"))
        #expect(NativeNotification.parseReply("6", for: sizes) == .invalid("Reply with 1–5 or your own answer"))
    }

    /// A number beyond the option count can only be a label.
    @Test func anOutOfRangeNumberMatchesALabelWhenNumbered() {
        let sizes = question("Which size?", ["1", "2", "4", "8", "16"])
        #expect(NativeNotification.parseReply("16", for: sizes) == .labels(["16"]))
        #expect(NativeNotification.parseReply("32", for: sizes) == .invalid("Reply with 1–5 or your own answer"))
        let amounts = question("How many?", ["10", "20", "30", "40", "50"])
        #expect(NativeNotification.parseReply("20", for: amounts) == .labels(["20"]))
        #expect(NativeNotification.parseReply("2", for: amounts) == .labels(["20"]))
        let multiSizes = question("Which sizes?", ["1", "2", "4", "8"], multi: true)
        #expect(NativeNotification.parseReply("8, 1", for: multiSizes) == .labels(["1", "8"]))
        #expect(
            NativeNotification.parseReply("16", for: multiSizes) == .invalid("Reply with option numbers, e.g. 1, 3"))
    }

    @Test func labelsContainingCommasMatchAsAWhole() {
        let colourPairs = question("Which pairs?", ["Red, green", "Blue", "Gold"], multi: true)
        #expect(NativeNotification.parseReply("red, GREEN", for: colourPairs) == .labels(["Red, green"]))
        #expect(NativeNotification.parseReply("1, 2", for: colourPairs) == .labels(["Red, green", "Blue"]))
        let single = question("Which pair?", ["Red, green", "Blue"])
        #expect(NativeNotification.parseReply("Red, Green", for: single) == .labels(["Red, green"]))
    }

    @Test(arguments: [
        ("1, 3", ["Blue", "Green"]), ("3,1", ["Blue", "Green"]), ("1 3", ["Blue", "Green"]),
        ("Purple, 2", ["Orange", "Purple"]), ("2, 2", ["Orange"]),
    ])
    func multiSelectReplies(_ text: String, _ expected: [String]) {
        #expect(NativeNotification.parseReply(text, for: likes) == .labels(expected))
    }

    @Test(arguments: ["", "1, x", "5", "0", "Teal"])
    func invalidMultiSelectReplies(_ text: String) {
        #expect(NativeNotification.parseReply(text, for: likes) == .invalid("Reply with option numbers, e.g. 1, 3"))
    }
}

@Suite struct NativeNotificationChangesTests {
    @Test func postsNewOrChangedAndRemovesGone() {
        let a = NotificationSpec(
            identifier: "a", threadIdentifier: "p", categoryIdentifier: "c", title: "A", body: "1", actions: [])
        let b = NotificationSpec(
            identifier: "b", threadIdentifier: "p", categoryIdentifier: "c", title: "B", body: "1", actions: [])
        var b2 = b
        b2.body = "2"  // e.g. the next question
        let c = NotificationSpec(
            identifier: "c", threadIdentifier: "p", categoryIdentifier: "c", title: "C", body: "1", actions: [])
        let changes = NativeNotification.changes(before: [a, b], after: [b2, c])
        #expect(changes.post.map(\.identifier) == ["b", "c"])
        #expect(changes.remove == ["a"])
        #expect(NativeNotification.changes(before: [a], after: [a]) == NotificationChanges(post: [], remove: []))
    }
}

@Suite struct TestNotificationTests {
    @Test func theTestNotificationHasAFixedIdAndNothingToAnswer() {
        let alert = NativeNotification.testSpec(alertStyle: .alert)
        #expect(alert.identifier == "hook-me-up-test")
        #expect(alert.categoryIdentifier.isEmpty)
        #expect(alert.actions.isEmpty)
        #expect(alert.title == "Hook Me Up")
        #expect(!alert.body.contains("Alerts"))
        #expect(NativeNotification.testSpec(alertStyle: .banner).body.contains("Set the style to Alerts"))
        #expect(UUID(uuidString: alert.identifier) == nil)  // can never be an entry's id
    }
}
