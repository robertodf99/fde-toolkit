import Foundation
import Testing

@testable import HookMeUpCore

/// Example inputs copied from code.claude.com/docs/en/hooks and from real hook runs
/// (paths and ids replaced), so parsing is checked against real shapes.
enum Fixtures {
    static let permissionRequestDocExample = #"""
        {
          "session_id": "abc123",
          "transcript_path": "/home/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
          "cwd": "/home/...",
          "permission_mode": "default",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {
            "command": "rm -rf node_modules",
            "description": "Remove node_modules directory"
          },
          "permission_suggestions": [
            {
              "type": "addRules",
              "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf node_modules" }],
              "behavior": "allow",
              "destination": "localSettings"
            }
          ]
        }
        """#

    /// A real Bash request, with the extra fields Claude Code sends.
    static let bashRequestWithExtraFields = #"""
        {"session_id":"00000000-0000-4000-8000-000000000001","transcript_path":"/tmp/t.jsonl","cwd":"/private/tmp/acme-api","scratchpad_dir":"/private/tmp/scratch","prompt_id":"977577c3-2605-43c1-8b70-f8b8059ef961","permission_mode":"default","effort":{"level":"medium"},"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"touch notes-again.txt","description":"Create empty file notes-again.txt"},"permission_suggestions":[{"type":"addDirectories","directories":["/private/tmp/acme-api"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]}
        """#

    static let notificationIdlePrompt = #"""
        {
          "session_id": "abc123",
          "transcript_path": "/home/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
          "cwd": "/home/...",
          "hook_event_name": "Notification",
          "message": "Claude is waiting for your input",
          "title": "Claude Code",
          "notification_type": "idle_prompt"
        }
        """#

    static let sessionEnd = #"""
        {
          "session_id": "abc123",
          "transcript_path": "/home/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
          "cwd": "/home/...",
          "hook_event_name": "SessionEnd",
          "reason": "other"
        }
        """#
}

func parse(_ json: String) throws -> HookInput {
    try HookInput.parse(Data(json.utf8))
}

@Suite struct ParsingTests {
    @Test func parsesPermissionRequestDocExample() throws {
        let input = try parse(Fixtures.permissionRequestDocExample)
        #expect(input.sessionID == "abc123")
        #expect(input.cwd == "/home/...")
        #expect(input.hookEventName == "PermissionRequest")
        #expect(input.permissionMode == "default")
        #expect(input.toolName == "Bash")
        #expect(
            input.toolInput
                == .object([
                    "command": .string("rm -rf node_modules"),
                    "description": .string("Remove node_modules directory"),
                ]))
        #expect(
            input.permissionSuggestions == [
                PermissionUpdate(
                    type: "addRules",
                    rules: [PermissionRule(toolName: "Bash", ruleContent: "rm -rf node_modules")],
                    behavior: "allow",
                    mode: nil,
                    directories: nil,
                    destination: "localSettings"
                )
            ])
        #expect(input.notificationType == nil)
    }

    @Test func parsesRealSuggestionsOfOtherTypes() throws {
        let input = try parse(Fixtures.bashRequestWithExtraFields)
        #expect(
            input.permissionSuggestions == [
                PermissionUpdate(
                    type: "addDirectories", rules: nil, behavior: nil, mode: nil,
                    directories: ["/private/tmp/acme-api"], destination: "session"),
                PermissionUpdate(
                    type: "setMode", rules: nil, behavior: nil, mode: "acceptEdits",
                    directories: nil, destination: "session"),
            ])
    }

    @Test func parsesNotificationIdlePrompt() throws {
        let input = try parse(Fixtures.notificationIdlePrompt)
        #expect(input.hookEventName == "Notification")
        #expect(input.notificationType == "idle_prompt")
        #expect(input.message == "Claude is waiting for your input")
        #expect(input.title == "Claude Code")
        #expect(input.toolName == nil)
        #expect(input.toolInput == nil)
        #expect(input.permissionSuggestions.isEmpty)
        #expect(input.permissionMode == nil)
    }

    @Test func parsesSessionEnd() throws {
        let input = try parse(Fixtures.sessionEnd)
        #expect(input.hookEventName == "SessionEnd")
        #expect(input.reason == "other")
        #expect(input.sessionID == "abc123")
    }

    @Test func unknownFieldsIgnored() throws {
        let input = try parse(Fixtures.bashRequestWithExtraFields)
        #expect(input.toolName == "Bash")
        // Unknown fields are not lost: they stay available in `raw`.
        #expect(input.raw["effort"] == .object(["level": .string("medium")]))
        #expect(input.raw["prompt_id"] == .string("977577c3-2605-43c1-8b70-f8b8059ef961"))
    }

    @Test func parsesSubagentAndMCPFields() throws {
        let input = try parse(
            #"""
            {"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"mcp__linear__save_issue",
             "tool_input":{"title":"x"},"agent_id":"agent-7","agent_type":"Explore",
             "mcp_server":{"name":"linear","source":"user"}}
            """#)
        #expect(input.agentID == "agent-7")
        #expect(input.agentType == "Explore")
        #expect(input.mcpServer == .object(["name": .string("linear"), "source": .string("user")]))
    }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        "\"just a string\"",
        "{}",
        #"{"cwd":"/p","hook_event_name":"Stop"}"#,  // no session_id
        #"{"session_id":"","cwd":"/p","hook_event_name":"Stop"}"#,  // empty session_id
        #"{"session_id":"s","hook_event_name":"Stop"}"#,  // no cwd
        #"{"session_id":"s","cwd":"/p"}"#,  // no hook_event_name
        #"{"session_id":7,"cwd":"/p","hook_event_name":"Stop"}"#,  // wrong type
        #"{"session_id":"s","cwd":"/p","hook_event_name":"Stop""#,  // truncated
    ])
    func garbageThrows(_ text: String) {
        #expect(throws: (any Error).self) { try parse(text) }
    }

    @Test func malformedSuggestionIsDroppedAloneNotTheWholeInput() throws {
        let input = try parse(
            #"""
            {"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{},
             "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash"}],"behavior":"allow"},
                                       "garbage",
                                       {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"ls"}],"behavior":"allow","destination":"session"}]}
            """#)
        #expect(
            input.permissionSuggestions == [
                PermissionUpdate(
                    type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "ls")],
                    behavior: "allow", mode: nil, directories: nil, destination: "session")
            ])
    }

    @Test func preservesRawToolInputExactly() throws {
        let input = try parse(
            #"""
            {"session_id":"s","cwd":"/p","hook_event_name":"PermissionRequest","tool_name":"Weird",
             "tool_input":{
               "text":"line1\nline2 \"quoted\" \\ back\/slash é 😀 tab\t",
               "int":600000, "neg":-3, "float":0.1, "zero":0,
               "yes":true, "no":false, "nothing":null,
               "list":[1,"1",true,null,[],{}],
               "nested":{"a":{"b":[{"c":"d"}]}}
             }}
            """#)
        let expected: JSONValue = .object([
            "text": .string("line1\nline2 \"quoted\" \\ back/slash é 😀 tab\t"),
            "int": .number(600000),
            "neg": .number(-3),
            "float": .number(0.1),
            "zero": .number(0),
            "yes": .bool(true),
            "no": .bool(false),
            "nothing": .null,
            "list": .array([.number(1), .string("1"), .bool(true), .null, .array([]), .object([:])]),
            "nested": .object(["a": .object(["b": .array([.object(["c": .string("d")])])])]),
        ])
        #expect(input.toolInput == expected)
        #expect(input.raw["tool_input"] == expected)
        // Round trip: encoding and decoding again gives the same value (true stays a bool, 1 a number).
        let reencoded = try JSONEncoder().encode(expected)
        #expect(try JSONDecoder().decode(JSONValue.self, from: reencoded) == expected)
    }

    @Test func prettyIsSortedAndIndented() {
        let value: JSONValue = .object(["b": .array([.number(1), .bool(true)]), "a": .string("x/y")])
        #expect(
            value.pretty() == """
                {
                  "a" : "x/y",
                  "b" : [
                    1,
                    true
                  ]
                }
                """)
    }

    @Test func subscriptOnlyReadsObjects() {
        #expect(JSONValue.array([.string("a")])["a"] == nil)
        #expect(JSONValue.object(["a": .null])["a"] == .null)
        #expect(JSONValue.object(["a": .null])["missing"] == nil)
    }
}

@Suite struct CodexWireTests {
    @Test func optionalClientLabelsFinishedWithoutChangingClaude() throws {
        for (extra, title) in [("", "proj · Finished"), (",\"client\":\"codex\"", "proj · Codex · Finished")] {
            let json =
                #"{"sessionID":"s","project":{"name":"proj"},"kind":"finished","message":"Done","terminal":{"ancestorPIDs":[]}\#(extra)}"#
            let note = try JSONDecoder().decode(NotifyEnvelope.self, from: Data(json.utf8))
            var core = AgentCore()
            _ = core.receive(.notify(note), from: 1, now: Date())
            let entry = try #require(core.store.entries.first)
            #expect(NativeNotification.spec(for: entry, request: nil, progress: nil).title == title)
        }
    }
}

extension CodexWireTests {
    @Test func codexPermissionSchemaAllowsNullTranscript() throws {
        let input = try HookInput.parse(
            Data(
                #"{"session_id":"codex-session","turn_id":"turn-1","cwd":"/tmp/test-project","hook_event_name":"PermissionRequest","model":"test-model","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"touch test.txt","description":"Create test file"},"transcript_path":null}"#
                    .utf8))
        #expect(input.sessionID == "codex-session")
        #expect(input.cwd == "/tmp/test-project")
        #expect(input.transcriptPath == nil)
        #expect(input.toolInput?["command"] == "touch test.txt")
        #expect(input.permissionSuggestions.isEmpty)
        #expect(input.raw["turn_id"] == "turn-1")
    }
}
