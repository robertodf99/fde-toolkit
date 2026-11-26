import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUp

/// AppleScript runs in an osascript child process (off the main thread).
@Suite struct AppleScriptRunnerTests {
    @Test func osascriptResultIsRead() {
        #expect(TerminalActivator.runAppleScript(#"return "found""#))
        #expect(!TerminalActivator.runAppleScript(#"return "missing""#))
        #expect(!TerminalActivator.runAppleScript("this is not applescript"))
    }
}

/// Arguments reach `on run argv` as they are, never as script text.
@Suite struct AppleScriptArgumentTests {
    private let echoFirst = """
        on run argv
          return item 1 of argv
        end run
        """

    @Test func argumentsGoToTheRunHandler() {
        #expect(TerminalActivator.runAppleScript(echoFirst, arguments: ["found"]))
        #expect(!TerminalActivator.runAppleScript(echoFirst, arguments: ["missing"]))
        let tricky = #"-e" & (do shell script "echo pwned") & ""#
        #expect(TerminalActivator.runAppleScriptOutput(echoFirst, arguments: [tricky]) == tricky + "\n")
        #expect(TerminalActivator.runAppleScriptOutput(echoFirst, arguments: ["--", "x"]) == "--\n")
        let count = "on run argv\nreturn count of argv\nend run"
        #expect(TerminalActivator.runAppleScriptOutput(count) == "0\n")
        #expect(TerminalActivator.runAppleScriptOutput(count, arguments: ["a b", "c"]) == "2\n")
    }

    @Test func failuresAndTimeoutsGiveNothing() {
        #expect(TerminalActivator.runAppleScriptOutput("error \"no\"") == nil)
        let start = Date()
        #expect(TerminalActivator.runAppleScriptOutput("delay 5\nreturn \"late\"", timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// More than a pipe holds (64 KiB): read while the script runs, so it doesn't block.
    @Test func longOutputIsReadWhole() {
        let long = "set s to \"x\"\nrepeat 17 times\nset s to s & s\nend repeat\nreturn s"
        #expect(TerminalActivator.runAppleScriptOutput(long)?.count == 131_073)
    }
}
