import Foundation
import Testing

@testable import HookMeUpCore

/// A real AskUserQuestion input (two questions, one multi-select).
private let askUserQuestionInput = #"""
    {"session_id":"session-question","cwd":"/private/tmp/acme-api","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which of these two colours do you prefer?","header":"Colour","options":[{"label":"Blue","description":"A calm, cool colour."},{"label":"Orange","description":"A warm, energetic colour."}],"multiSelect":false},{"question":"Which of these colours do you like? Select as many as you want.","header":"Likes","options":[{"label":"Blue","description":"Cool and calm."},{"label":"Orange","description":"Warm and energetic."},{"label":"Green","description":"Fresh and natural."},{"label":"Purple","description":"Rich and bold."}],"multiSelect":true}]}}
    """#

/// An ExitPlanMode input (plan text with newlines and quotes).
private let exitPlanModeInput = #"""
    {"session_id":"session-plan","cwd":"/private/tmp/acme-api","permission_mode":"plan","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"# Plan: create hello.txt\n\n## Steps\n1. Create `hello.txt` with \"hello\\n\".\n","planFilePath":"/home/x/.claude/plans/plan-a-tiny-change.md"}}
    """#

private let q1 = "Which of these two colours do you prefer?"
private let q2 = "Which of these colours do you like? Select as many as you want."

private func outputString(_ decision: UserDecision, _ input: HookInput) -> String? {
    DecisionEncoder.output(for: decision, input: input).map { String(decoding: $0, as: UTF8.self) }
}

private func outputJSON(_ decision: UserDecision, _ input: HookInput) throws -> JSONValue? {
    guard let data = DecisionEncoder.output(for: decision, input: input) else { return nil }
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

private func bashInput(suggestions: String = "[]") throws -> HookInput {
    try parse(
        #"""
        {"session_id":"s","cwd":"/p","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"command":"touch x","description":"Create x"},"permission_suggestions":\#(suggestions)}
        """#)
}

/// Every `destination` value and every update `type` found anywhere in the output.
private func collect(_ value: JSONValue, destinations: inout [String], types: inout [String]) {
    switch value {
    case .object(let members):
        if let destination = members["destination"] { destinations.append(destination.stringValue ?? "<non-string>") }
        if members["destination"] != nil, let type = members["type"] {
            types.append(type.stringValue ?? "<non-string>")
        }
        for member in members.values { collect(member, destinations: &destinations, types: &types) }
    case .array(let items):
        for item in items { collect(item, destinations: &destinations, types: &types) }
    default:
        break
    }
}

private let allDecisions: [UserDecision] = [
    .approve, .approveForSession, .deny, .answer([q1: "Blue"]), .approvePlan,
    .requestChanges("Add a test step."), .openInTerminal,
]

@Suite struct DecisionEncoderTests {
    @Test func approveProducesExactAllowJSON() throws {
        #expect(
            outputString(.approve, try bashInput())
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    }

    @Test func denyUsesFixedMessage() throws {
        #expect(
            outputString(.deny, try bashInput())
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"User denied this via a notification. Don't retry the same action; ask or try another approach."}}}"#
        )
        #expect(
            DecisionEncoder.denyMessage
                == "User denied this via a notification. Don't retry the same action; ask or try another approach.")
    }

    @Test func openInTerminalProducesNil() throws {
        for input in [try bashInput(), try parse(askUserQuestionInput), try parse(exitPlanModeInput)] {
            #expect(DecisionEncoder.output(for: .openInTerminal, input: input) == nil)
        }
    }

    @Test func noDecisionForAnyEventOtherThanPermissionRequest() throws {
        let notification = try parse(Fixtures.notificationIdlePrompt)
        let stop = try parse(
            #"{"session_id":"s","cwd":"/p","hook_event_name":"Stop","tool_name":"Bash","tool_input":{}}"#)
        for input in [notification, stop] {
            for decision in allDecisions {
                #expect(DecisionEncoder.output(for: decision, input: input) == nil)
            }
        }
    }

    @Test func noDecisionWithoutToolName() throws {
        let input = try parse(#"{"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_input":{}}"#)
        for decision in allDecisions {
            #expect(DecisionEncoder.output(for: decision, input: input) == nil)
        }
    }

    @Test func approveForSessionForcesSessionDestination() throws {
        let input = try bashInput(
            suggestions: #"""
                [{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch x"}],"behavior":"allow","destination":"localSettings"},
                 {"type":"addDirectories","directories":["/p/sub"],"destination":"userSettings"}]
                """#)
        #expect(
            try outputJSON(.approveForSession, input)
                == .object([
                    "hookSpecificOutput": .object([
                        "hookEventName": .string("PermissionRequest"),
                        "decision": .object([
                            "behavior": .string("allow"),
                            "updatedPermissions": .array([
                                .object([
                                    "type": .string("addRules"),
                                    "rules": .array([
                                        .object(["toolName": .string("Bash"), "ruleContent": .string("touch x")])
                                    ]),
                                    "behavior": .string("allow"),
                                    "destination": .string("session"),
                                ]),
                                .object([
                                    "type": .string("addDirectories"),
                                    "directories": .array([.string("/p/sub")]),
                                    "destination": .string("session"),
                                ]),
                            ]),
                        ]),
                    ])
                ]))
    }

    @Test func approveForSessionDropsNonAddTypes() throws {
        // Real suggestions: addDirectories + setMode(acceptEdits). setMode must go.
        let input = try parse(Fixtures.bashRequestWithExtraFields)
        let json = try #require(try outputJSON(.approveForSession, input))
        let kept = json["hookSpecificOutput"]?["decision"]?["updatedPermissions"]
        #expect(
            kept
                == .array([
                    .object([
                        "type": .string("addDirectories"),
                        "directories": .array([.string("/private/tmp/acme-api")]),
                        "destination": .string("session"),
                    ])
                ]))
    }

    @Test func approveForSessionKeepsOnlyAllowRules() throws {
        let input = try bashInput(
            suggestions: #"""
                [{"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"deny","destination":"session"},
                 {"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"ask","destination":"session"},
                 {"type":"addRules","rules":[],"behavior":"allow","destination":"session"},
                 {"type":"addDirectories","directories":[],"destination":"session"}]
                """#)
        // Nothing survives, so this is a plain allow.
        #expect(
            outputString(.approveForSession, input)
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    }

    @Test func approveForSessionWithNoSurvivorsFallsBackToPlainApprove() throws {
        let input = try bashInput(
            suggestions: #"""
                [{"type":"setMode","mode":"bypassPermissions","destination":"session"},
                 {"type":"replaceRules","rules":[{"toolName":"Bash"}],"behavior":"allow","destination":"userSettings"}]
                """#)
        #expect(
            outputString(.approveForSession, input)
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
        #expect(
            outputString(.approveForSession, try bashInput())
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    }

    @Test func noOutputEverContainsNonSessionDestination() throws {
        let types = [
            "addRules", "replaceRules", "removeRules", "setMode", "addDirectories", "removeDirectories", "somethingNew",
        ]
        let destinations = [
            "session", "localSettings", "projectSettings", "userSettings", "policySettings", "", "SESSION",
        ]
        // Exhaustive: each type x destination, one at a time and all together.
        var everything: [String] = []
        for type in types {
            for destination in destinations {
                let entry =
                    #"{"type":"\#(type)","rules":[{"toolName":"Bash","ruleContent":"x"}],"behavior":"allow","mode":"bypassPermissions","directories":["/etc"],"destination":"\#(destination)"}"#
                everything.append(entry)
                try check(suggestions: "[\(entry)]")
            }
        }
        try check(suggestions: "[\(everything.joined(separator: ","))]")

        // Seeded random combinations (property test).
        var rng = SplitMix64(seed: 0xC1A0DE)
        for _ in 0..<300 {
            let count = Int(rng.next() % 6)
            let entries = (0..<count).map { _ -> String in
                let type = types[Int(rng.next() % UInt64(types.count))]
                let destination = destinations[Int(rng.next() % UInt64(destinations.count))]
                let behavior = ["allow", "deny", "ask"][Int(rng.next() % 3)]
                return
                    #"{"type":"\#(type)","rules":[{"toolName":"Bash"}],"behavior":"\#(behavior)","mode":"dontAsk","directories":["/"],"destination":"\#(destination)"}"#
            }
            try check(suggestions: "[\(entries.joined(separator: ","))]")
        }

        func check(suggestions: String) throws {
            let input = try bashInput(suggestions: suggestions)
            for decision in allDecisions {
                guard let json = try outputJSON(decision, input) else { continue }
                var seenDestinations: [String] = []
                var seenTypes: [String] = []
                collect(json, destinations: &seenDestinations, types: &seenTypes)
                #expect(seenDestinations.allSatisfy { $0 == "session" }, "\(decision) leaked \(seenDestinations)")
                #expect(
                    seenTypes.allSatisfy { $0 == "addRules" || $0 == "addDirectories" },
                    "\(decision) leaked \(seenTypes)")
                let text = String(
                    decoding: try #require(DecisionEncoder.output(for: decision, input: input)), as: UTF8.self)
                #expect(!text.contains("Settings"), "\(decision): \(text)")
                #expect(!text.contains("setMode") && !text.contains("bypassPermissions") && !text.contains("dontAsk"))
            }
        }
    }

    @Test func answerOnlyForAskUserQuestion() throws {
        #expect(DecisionEncoder.output(for: .answer(["Create x": "yes"]), input: try bashInput()) == nil)
        #expect(DecisionEncoder.output(for: .answer([q1: "Blue"]), input: try parse(exitPlanModeInput)) == nil)
    }

    @Test func answerUpdatedInputEqualsOriginalPlusAnswers() throws {
        let input = try parse(askUserQuestionInput)
        let json = try #require(try outputJSON(.answer([q1: "Orange", q2: "Green"]), input))
        let expectedUpdatedInput = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(
                #"""
                {"questions":[{"question":"Which of these two colours do you prefer?","header":"Colour","options":[{"label":"Blue","description":"A calm, cool colour."},{"label":"Orange","description":"A warm, energetic colour."}],"multiSelect":false},{"question":"Which of these colours do you like? Select as many as you want.","header":"Likes","options":[{"label":"Blue","description":"Cool and calm."},{"label":"Orange","description":"Warm and energetic."},{"label":"Green","description":"Fresh and natural."},{"label":"Purple","description":"Rich and bold."}],"multiSelect":true}],
                 "answers":{"Which of these two colours do you prefer?":"Orange","Which of these colours do you like? Select as many as you want.":"Green"}}
                """#.utf8))
        #expect(
            json
                == .object([
                    "hookSpecificOutput": .object([
                        "hookEventName": .string("PermissionRequest"),
                        "decision": .object(["behavior": .string("allow"), "updatedInput": expectedUpdatedInput]),
                    ])
                ]))
    }

    @Test func answerReplacesAnyAnswersAlreadyInToolInput() throws {
        let input = try parse(
            #"""
            {"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion",
             "tool_input":{"questions":[{"question":"Q?","options":[{"label":"A"}],"multiSelect":false}],"answers":{"Q?":"planted","Other?":"x"}}}
            """#)
        let json = try #require(try outputJSON(.answer(["Q?": "A"]), input))
        #expect(json["hookSpecificOutput"]?["decision"]?["updatedInput"]?["answers"] == .object(["Q?": .string("A")]))
    }

    @Test func answerMustCoverExactlyTheHooksOwnQuestions() throws {
        let input = try parse(askUserQuestionInput)
        // Missing a question, an unknown question, and an empty answer: all fall back to the terminal.
        #expect(DecisionEncoder.output(for: .answer([q1: "Blue"]), input: input) == nil)
        #expect(DecisionEncoder.output(for: .answer([q1: "Blue", q2: "Green", "Injected?": "x"]), input: input) == nil)
        #expect(DecisionEncoder.output(for: .answer([q1: "Blue", q2: "  "]), input: input) == nil)
        #expect(DecisionEncoder.output(for: .answer([:]), input: input) == nil)
    }

    @Test func noAnswerWhenTheHooksQuestionsRepeatAText() throws {
        // Two questions with the same text cannot be told apart in `answers`: terminal.
        let input = try parse(
            #"{"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which?","options":[{"label":"A"}]},{"question":"Which?","options":[{"label":"B"}]}]}}"#
        )
        #expect(DecisionEncoder.output(for: .answer(["Which?": "A"]), input: input) == nil)
    }

    @Test func answerAcceptsOtherFreeText() throws {
        let input = try parse(askUserQuestionInput)
        let json = try #require(try outputJSON(.answer([q1: "Teal, typed in the popup", q2: "Blue"]), input))
        #expect(
            json["hookSpecificOutput"]?["decision"]?["updatedInput"]?["answers"]?[q1]
                == .string("Teal, typed in the popup"))
    }

    @Test func multiSelectJoinedWithCommaSpace() throws {
        let input = try parse(askUserQuestionInput)
        let decision = UserDecision.answer(selections: [q1: ["Blue"], q2: ["Blue", "Orange", "Teal (other)"]])
        #expect(decision == .answer([q1: "Blue", q2: "Blue, Orange, Teal (other)"]))
        let json = try #require(try outputJSON(decision, input))
        #expect(
            json["hookSpecificOutput"]?["decision"]?["updatedInput"]?["answers"]?[q2]
                == .string("Blue, Orange, Teal (other)"))
    }

    @Test func approvePlanOnlyForExitPlanMode() throws {
        let plan = try parse(exitPlanModeInput)
        let json = try #require(try outputJSON(.approvePlan, plan))
        // updatedInput is the hook's own tool_input, unchanged.
        #expect(
            json
                == .object([
                    "hookSpecificOutput": .object([
                        "hookEventName": .string("PermissionRequest"),
                        "decision": .object([
                            "behavior": .string("allow"),
                            "updatedInput": .object([
                                "plan": .string(
                                    "# Plan: create hello.txt\n\n## Steps\n1. Create `hello.txt` with \"hello\\n\".\n"),
                                "planFilePath": .string("/home/x/.claude/plans/plan-a-tiny-change.md"),
                            ]),
                        ]),
                    ])
                ]))
        #expect(DecisionEncoder.output(for: .approvePlan, input: try bashInput()) == nil)
        #expect(DecisionEncoder.output(for: .approvePlan, input: try parse(askUserQuestionInput)) == nil)
    }

    @Test func plainApproveIsRefusedForQuestionsAndPlans() throws {
        // These tools need updatedInput; a plain allow would not carry the user's answer.
        for input in [try parse(askUserQuestionInput), try parse(exitPlanModeInput)] {
            #expect(DecisionEncoder.output(for: .approve, input: input) == nil)
            #expect(DecisionEncoder.output(for: .approveForSession, input: input) == nil)
        }
    }

    @Test func requestChangesIsDenyWithFeedback() throws {
        #expect(
            outputString(.requestChanges("Please add a testing step to the plan."), try parse(exitPlanModeInput))
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Please add a testing step to the plan."}}}"#
        )
        #expect(DecisionEncoder.output(for: .requestChanges("Change it"), input: try bashInput()) == nil)
    }

    @Test func requestChangesEmptyFeedbackIsNil() throws {
        let plan = try parse(exitPlanModeInput)
        #expect(DecisionEncoder.output(for: .requestChanges(""), input: plan) == nil)
        #expect(DecisionEncoder.output(for: .requestChanges("  \n\t "), input: plan) == nil)
    }

    @Test func outputIsByteForByteDeterministic() throws {
        // JSONEncoder alone does not keep key order stable; the printed JSON must be.
        let input = try parse(Fixtures.bashRequestWithExtraFields)
        let plan = try parse(exitPlanModeInput)
        for (decision, hookInput) in [
            (UserDecision.approve, input), (.deny, input), (.approveForSession, input), (.approvePlan, plan),
        ] {
            let first = try #require(DecisionEncoder.output(for: decision, input: hookInput))
            for _ in 0..<50 {
                #expect(DecisionEncoder.output(for: decision, input: hookInput) == first)
            }
        }
        #expect(
            outputString(.approveForSession, input)
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"destination":"session","directories":["/private/tmp/acme-api"],"type":"addDirectories"}]}}}"#
        )
    }

    @Test func controlCharactersRoundTrip() throws {
        let input = try parse(askUserQuestionInput)
        let tricky = "tab\t nul-ish \u{0001} quote\" back\\slash \u{2028} emoji 😀 é"
        let json = try #require(try outputJSON(.answer([q1: tricky, q2: "Blue"]), input))
        #expect(json["hookSpecificOutput"]?["decision"]?["updatedInput"]?["answers"]?[q1] == .string(tricky))
    }

    @Test func outputIsSingleLineValidJSON() throws {
        let inputs = [
            try parse(Fixtures.bashRequestWithExtraFields), try parse(askUserQuestionInput),
            try parse(exitPlanModeInput),
        ]
        let decisions: [UserDecision] =
            allDecisions + [
                .answer([q1: "line\nbreak", q2: "Blue"]),
                .requestChanges("First line\nSecond \"line\""),
            ]
        var produced = 0
        for input in inputs {
            for decision in decisions {
                guard let data = DecisionEncoder.output(for: decision, input: input) else { continue }
                produced += 1
                #expect(!data.contains(UInt8(ascii: "\n")) && !data.contains(UInt8(ascii: "\r")))
                #expect((try? JSONSerialization.jsonObject(with: data)) is [String: Any])
            }
        }
        #expect(produced >= 6)
    }
}

/// Deterministic generator so the property test is reproducible.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct CodexDecisionTests {
    @Test func codexHasOnlyTwoMinimalDecisions() throws {
        let input = try bashInput()
        for decision in allDecisions {
            let data = DecisionEncoder.output(for: decision, input: input, client: .codex)
            switch decision {
            case .approve:
                #expect(
                    data.map { String(decoding: $0, as: UTF8.self) }
                        == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
                )
            case .deny:
                let value = try JSONDecoder().decode(JSONValue.self, from: #require(data))
                #expect(Set(value.objectValue!.keys) == ["hookSpecificOutput"])
                let output = value["hookSpecificOutput"]!
                #expect(Set(output.objectValue!.keys) == ["hookEventName", "decision"])
                #expect(output["hookEventName"] == "PermissionRequest")
                #expect(Set(output["decision"]!.objectValue!.keys) == ["behavior", "message"])
                #expect(output["decision"]?["behavior"] == "deny")
            default: #expect(data == nil)
            }
        }
        for json in [askUserQuestionInput, exitPlanModeInput] {
            for decision in allDecisions {
                #expect(DecisionEncoder.output(for: decision, input: try parse(json), client: .codex) == nil)
            }
        }
    }
}
