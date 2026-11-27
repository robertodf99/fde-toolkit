import Foundation
import Testing

@testable import HookMeUp

@Suite struct HerdrFocusTests {
    @Test func focusUsesSeparateArguments() {
        let executable = URL(fileURLWithPath: "/test/Herdr.app/Contents/MacOS/Herdr")
        var called = false
        let result = TerminalActivator.herdrFocus(id: "test-pane_1", executable: executable) { url, arguments in
            called = true
            #expect(url == executable)
            #expect(arguments == ["do", "agent.focus", "--terminal", "test-pane_1"])
            return "{\"ok\":true}\n"
        }
        #expect(called)
        #expect(result == .focused)
    }

    @Test(arguments: [nil, "", "a b", "$(id)", "pane\n", String(repeating: "a", count: 65)])
    func missingOrInvalidIDNeverRunsACommand(_ id: String?) {
        let result = TerminalActivator.herdrFocus(id: id, executable: URL(fileURLWithPath: "/test/Herdr")) { _, _ in
            Issue.record("Invalid terminal must not run a command")
            return nil
        }
        #expect(result == .noTerminal)
    }

    @Test func noExecutableOrFailedCommandFallsBack() {
        #expect(
            TerminalActivator.herdrFocus(id: "test-pane_1", executable: nil) { _, _ in
                Issue.record("Missing app must not run a command")
                return nil
            } == .unavailable)
        #expect(
            TerminalActivator.herdrFocus(id: "test-pane_1", executable: URL(fileURLWithPath: "/test/Herdr")) { _, _ in
                nil
            } == .commandFailed)
    }

    @Test func processRunnerPreservesArgumentsAndHandlesFailuresAndTimeout() {
        let arguments = ["do", "agent.focus", "--terminal", "test-pane_1", "$(id); echo unsafe", "a b"]
        #expect(
            TerminalActivator.runProcessOutput(
                executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s\n"] + arguments)
                == arguments.joined(separator: "\n") + "\n")
        #expect(
            TerminalActivator.runProcessOutput(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: []) == nil
        )
        #expect(
            TerminalActivator.runProcessOutput(executable: URL(fileURLWithPath: "/nonexistent/Herdr"), arguments: [])
                == nil)
        let start = Date()
        #expect(
            TerminalActivator.runProcessOutput(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
