import Foundation
import Testing

@testable import HookMeUpCore

/// A real ancestor chain of a hook run from Terminal:
/// claude -> /bin/zsh -> Code Helper -> Visual Studio Code.
private let vsCodeChain: [(pid: pid_t, path: String)] = [
    (12325, "/home/me/.local/share/claude/versions/2.1/claude"),
    (11010, "/bin/zsh"),
    (964, "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
    (935, "/Applications/Visual Studio Code.app/Contents/MacOS/Code"),
]

/// Bundle IDs as Info.plist would report them (the helper has its own ID).
private func bundleID(_ appPath: String) -> String? {
    [
        "/Applications/Visual Studio Code.app": "com.microsoft.VSCode",
        "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app": "com.microsoft.VSCode.helper",
        "/Applications/Cursor.app": "com.todesktop.230313mzl4w4u92",
        "/System/Applications/Utilities/Terminal.app": "com.apple.Terminal",
        "/Applications/iTerm.app": "com.googlecode.iterm2",
        "/Applications/Alacritty.app": "org.alacritty",
    ][appPath]
}

@Suite struct TerminalMappingTests {
    @Test func bundleIDMappingForKnownTerminals() {
        #expect(TerminalApp(bundleID: "com.apple.Terminal") == .appleTerminal)
        #expect(TerminalApp(bundleID: "com.googlecode.iterm2") == .iTerm2)
        #expect(TerminalApp(bundleID: "com.mitchellh.ghostty") == .ghostty)
        #expect(TerminalApp(bundleID: "dev.warp.Warp-Stable") == .warp)
        #expect(TerminalApp(bundleID: "com.microsoft.VSCode") == .vsCode)
        #expect(TerminalApp(bundleID: "com.microsoft.VSCodeInsiders") == .vsCode)
        #expect(TerminalApp(bundleID: "com.todesktop.230313mzl4w4u92") == .cursor)
        #expect(TerminalApp(bundleID: "com.anthropic.claudefordesktop") == .claudeDesktop)
        #expect(TerminalApp(bundleID: "com.microsoft.VSCode.helper") == nil)
        #expect(TerminalApp.appleTerminal.selectsTabByTTY && TerminalApp.iTerm2.selectsTabByTTY)
        #expect(![TerminalApp.ghostty, .warp, .vsCode, .cursor, .claudeDesktop].contains { $0.selectsTabByTTY })
    }

    @Test func outermostAppBundle() {
        #expect(
            TerminalMapping.outermostAppBundle(ofExecutable: vsCodeChain[2].path)
                == "/Applications/Visual Studio Code.app")
        #expect(
            TerminalMapping.outermostAppBundle(
                ofExecutable: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
                == "/System/Applications/Utilities/Terminal.app")
        #expect(TerminalMapping.outermostAppBundle(ofExecutable: "/bin/zsh") == nil)
        #expect(TerminalMapping.outermostAppBundle(ofExecutable: "") == nil)
    }

    @Test func vsCodeHelperChainResolvesToTheParentApp() {
        let owner = TerminalMapping.owner(ancestors: vsCodeChain, bundleID: bundleID)
        #expect(
            owner
                == TerminalMapping.Owner(
                    bundleID: "com.microsoft.VSCode",
                    appPath: "/Applications/Visual Studio Code.app", pid: 935))
    }

    @Test func cursorChainResolves() {
        let chain: [(pid: pid_t, path: String)] = [
            (50, "/opt/homebrew/bin/node"), (49, "/bin/zsh"),
            (
                40,
                "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)"
            ),
            (30, "/Applications/Cursor.app/Contents/MacOS/Cursor"),
        ]
        #expect(
            TerminalMapping.owner(ancestors: chain, bundleID: bundleID)?.bundleID == "com.todesktop.230313mzl4w4u92")
        #expect(TerminalMapping.owner(ancestors: chain, bundleID: bundleID)?.pid == 30)
    }

    @Test func terminalAndUnknownApps() {
        let terminal: [(pid: pid_t, path: String)] = [
            (5, "/bin/zsh"), (4, "/usr/bin/login"),
            (3, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
        ]
        #expect(TerminalMapping.owner(ancestors: terminal, bundleID: bundleID)?.bundleID == "com.apple.Terminal")
        // An app we do not know is still the owner (app-level activation).
        let alacritty: [(pid: pid_t, path: String)] = [
            (9, "/bin/zsh"), (8, "/Applications/Alacritty.app/Contents/MacOS/alacritty"),
        ]
        #expect(TerminalMapping.owner(ancestors: alacritty, bundleID: bundleID)?.bundleID == "org.alacritty")
        // tmux server or ssh: no app in the chain.
        #expect(
            TerminalMapping.owner(ancestors: [(9, "/bin/zsh"), (8, "/opt/homebrew/bin/tmux")], bundleID: bundleID)
                == nil)
    }

    @Test func tabScriptsOnlyForSafeTTYs() throws {
        let script = try #require(TerminalScripts.selectTab(.appleTerminal, tty: "ttys003"))
        #expect(script.contains(#"tell application "Terminal""#))
        #expect(script.contains(#"is "/dev/ttys003""#))
        #expect(
            TerminalScripts.selectTab(.iTerm2, tty: "/dev/ttys012")?.contains(#"tell application "iTerm2""#) == true)
        for bad in [#"ttys003" & (do shell script "id") & ""#, "ttys003\n", "../ttys1", "", "console", "tty s1"] {
            #expect(TerminalScripts.selectTab(.appleTerminal, tty: bad) == nil, "\(bad)")
        }
        #expect(TerminalScripts.selectTab(.vsCode, tty: "ttys003") == nil)  // not scriptable: app activation only
    }
}
