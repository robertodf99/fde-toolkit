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
