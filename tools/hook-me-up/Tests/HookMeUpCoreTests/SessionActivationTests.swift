import Foundation
import Testing

@testable import HookMeUpCore

/// A file system with only the folders and files it is given.
private struct FakeFileSystem: FileSystem {
    var folders: Set<String> = []
    var files: [String: Data] = [:]

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let folder = folders.contains(path)
        isDirectory?.pointee = ObjCBool(folder)
        return folder || files[path] != nil
    }

    func contents(atPath path: String) -> Data? { files[path] }
}

private let home = "/Users/dev"

private func storagePath(_ editor: String) -> String {
    "\(home)/Library/Application Support/\(editor)/User/globalStorage/storage.json"
}

/// VS Code's window state with windows open on `folders`, the first one last active.
private func windowState(_ folders: [String]) -> Data {
    let entries = folders.map { #"{"folder": "file://\#($0)"}"# }
    let text =
        #"{"windowsState": {"lastActiveWindow": \#(entries[0]), "openedWindows": [\#(entries.joined(separator: ", "))]}}"#
    return Data(text.utf8)
}

private let projects = "\(home)/projects"

/// Two repositories, a worktree and a subfolder; VS Code (and the other editors) have windows
/// open on the two repositories.
private let disk: FakeFileSystem = {
    var disk = FakeFileSystem(
        folders: [
            "\(projects)/acme-api", "\(projects)/acme-api/.claude/worktrees/login", "\(projects)/acme-web",
            "\(projects)/acme-web/src", "\(projects)/scratch",
        ],
        files: [:])
    disk.files["\(home)/notes.txt"] = Data("notes".utf8)
    for editor in ["Code", "Code - Insiders", "Cursor", "Windsurf"] {
        disk.files[storagePath(editor)] = windowState(["\(projects)/acme-web", "\(projects)/acme-api"])
    }
    return disk
}()

private func plan(
    _ bundleID: String?, tty: String? = nil, folder: String? = nil, fileSystem: FakeFileSystem = disk,
    sessionAlive: Bool = true, openWindows: Int = 2
) -> SessionActivation {
    SessionActivation.plan(
        ownerBundleID: bundleID, tty: tty, folder: folder, home: home, fileSystem: fileSystem,
        sessionAlive: sessionAlive, openWindowCount: { openWindows })
}

private let vsCodeFamily = [
    "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
    "com.exafunction.windsurf",
]

@Suite struct SessionActivationTests {
    @Test(arguments: ["dev.herdr.core", "dev.herdr.app"])
    func herdrFocusesItsTerminalOrOnlyComesForward(_ bundleID: String) {
        for id: String? in ["test-pane_1", nil, "", "bad id", "pane\n", String(repeating: "x", count: 65)] {
            let result = SessionActivation.plan(
                ownerBundleID: bundleID, tty: "ttys003", folder: nil, home: home, fileSystem: disk,
                herdrTerminal: id, sessionAlive: true,
                openWindowCount: {
                    Issue.record("Herdr must not count windows")
                    return 0
                })
            #expect(result == (id == "test-pane_1" ? .focusHerdrTerminal(id: "test-pane_1") : .activateApp))
        }
    }

    @Test func herdrHintDoesNotChangeOtherTerminals() {
        let result = SessionActivation.plan(
            ownerBundleID: "com.apple.Terminal", tty: "ttys003", folder: nil, home: home, fileSystem: disk,
            herdrTerminal: "test-pane_1", sessionAlive: true, openWindowCount: { 0 })
        #expect(result == .selectTab(.appleTerminal, tty: "ttys003"))
    }

    @Test func terminalAndITermSelectTheTab() {
        #expect(plan("com.apple.Terminal", tty: "ttys003") == .selectTab(.appleTerminal, tty: "ttys003"))
        #expect(plan("com.googlecode.iterm2", tty: "/dev/ttys012") == .selectTab(.iTerm2, tty: "/dev/ttys012"))
        // Without a usable tty they are just brought forward.
        #expect(plan("com.apple.Terminal") == .activateApp)
        #expect(plan("com.apple.Terminal", tty: "not a tty") == .activateApp)
    }

    /// VS Code, Insiders, Cursor and Windsurf focus the open window that holds the session's
    /// folder: the folder itself, a worktree inside it or a subfolder.
    @Test(arguments: vsCodeFamily)
    func editorsFocusTheWindowThatHoldsTheFolder(_ bundleID: String) {
        #expect(plan(bundleID, tty: "ttys003", folder: "\(projects)/acme-api") == .focusWindow("\(projects)/acme-api"))
        #expect(
            plan(bundleID, folder: "\(projects)/acme-api/.claude/worktrees/login")
                == .focusWindow("\(projects)/acme-api"))
        #expect(plan(bundleID, folder: "\(projects)/acme-web/src/") == .focusWindow("\(projects)/acme-web"))
    }

    /// No open window holds the folder: the editor only comes forward, so the click opens no
    /// new window.
    @Test(arguments: vsCodeFamily)
    func noMatchingWindowBringsTheEditorForward(_ bundleID: String) {
        #expect(plan(bundleID, folder: "\(projects)/scratch") == .activateApp)
    }

    /// The session's process is gone (its window was closed, say): the recorded window may be
    /// gone too, so nothing is opened.
    @Test(arguments: vsCodeFamily)
    func aFinishedSessionOnlyBringsTheEditorForward(_ bundleID: String) {
        #expect(plan(bundleID, folder: "\(projects)/acme-api", sessionAlive: false) == .activateApp)
    }

    /// The editor has no window open (VS Code still records the last one closed): nothing is
    /// opened. Terminals don't count windows.
    @Test(arguments: vsCodeFamily)
    func anEditorWithNoWindowOpenIsOnlyBroughtForward(_ bundleID: String) {
        #expect(plan(bundleID, folder: "\(projects)/acme-api", openWindows: 0) == .activateApp)
        #expect(plan(bundleID, folder: "\(projects)/acme-api", openWindows: 1) == .focusWindow("\(projects)/acme-api"))
        var counted = false
        let terminal = SessionActivation.plan(
            ownerBundleID: "com.apple.Terminal", tty: "ttys003", folder: "\(projects)/acme-api", home: home,
            fileSystem: disk, sessionAlive: false,
            openWindowCount: {
                counted = true
                return 0
            })
        #expect(terminal == .selectTab(.appleTerminal, tty: "ttys003"))
        #expect(!counted)
    }

    @Test(arguments: [nil, Data("{\"windowsState\": ".utf8), Data("[]".utf8), Data()])
    func missingOrMalformedWindowStateBringsTheEditorForward(_ contents: Data?) {
        var broken = disk
        broken.files[storagePath("Code")] = contents
        #expect(plan("com.microsoft.VSCode", folder: "\(projects)/acme-api", fileSystem: broken) == .activateApp)
    }

    @Test func oversizedWindowStateIsNotRead() {
        var big = disk
        var data = windowState(["\(projects)/acme-api"])
        data.append(Data(count: EditorWindows.maxStorageBytes))
        big.files[storagePath("Code")] = data
        #expect(plan("com.microsoft.VSCode", folder: "\(projects)/acme-api", fileSystem: big) == .activateApp)
    }

    /// Only an existing absolute folder is looked up; otherwise the editor is just brought
    /// forward (even with a window open on the whole disk).
    @Test(arguments: [nil, "", "projects/acme-api", "\(projects)/missing", "\(home)/notes.txt"])
    func editorsWithoutAUsableFolderAreBroughtForward(_ folder: String?) {
        var wide = disk
        wide.folders.insert("/")
        wide.files[storagePath("Code")] = windowState(["/"])
        #expect(plan("com.microsoft.VSCode", folder: folder, fileSystem: wide) == .activateApp)
    }

    /// Zed keeps no window state that can be read, and opening a folder could create a window.
    @Test(arguments: ["dev.zed.Zed", "dev.zed.Zed-Preview"])
    func zedIsBroughtForward(_ bundleID: String) {
        #expect(plan(bundleID, tty: "ttys003", folder: "\(projects)/acme-api") == .activateApp)
    }

    @Test(arguments: ["dev.warp.Warp-Stable", "com.anthropic.claudefordesktop", "org.example.app"])
    func otherAppsAreBroughtForward(_ bundleID: String) {
        #expect(plan(bundleID, tty: "ttys003", folder: "\(projects)/acme-api") == .activateApp)
    }

    /// Ghostty focuses the terminal in the session's folder (normalised), with the session's
    /// tty as a device path when it has one (for the title marker); the session's process
    /// and window count don't matter.
    @Test func ghosttyLooksForTheTerminalInTheFolder() {
        let ghostty = "com.mitchellh.ghostty"
        #expect(
            plan(ghostty, tty: "ttys003", folder: "\(projects)/acme-api")
                == .focusTerminalByFolder(.ghostty, folder: "\(projects)/acme-api", tty: "/dev/ttys003"))
        #expect(
            plan(ghostty, folder: "\(projects)/acme-web/src/", sessionAlive: false, openWindows: 0)
                == .focusTerminalByFolder(.ghostty, folder: "\(projects)/acme-web/src", tty: nil))
    }

    /// Only a plain pseudo-terminal is kept; anything else still looks for the terminal by
    /// folder, without a tty (so no title marker is written).
    @Test(
        arguments: [
            ("/dev/ttys012", "/dev/ttys012"), ("ttys1023", "/dev/ttys1023"), ("ttys0", nil), ("../ttys003", nil),
            ("not a tty", nil), ("/dev/console", nil), ("ttys003\"", nil),
        ] as [(String, String?)])
    func ghosttyKeepsOnlyAPlainPseudoTerminal(_ tty: String, _ path: String?) {
        #expect(
            plan("com.mitchellh.ghostty", tty: tty, folder: "\(projects)/acme-api")
                == .focusTerminalByFolder(.ghostty, folder: "\(projects)/acme-api", tty: path))
    }

    /// Without an existing absolute folder, Ghostty only comes forward.
    @Test(arguments: [nil, "", "projects/acme-api", "\(projects)/missing", "\(home)/notes.txt"])
    func ghosttyWithoutAUsableFolderIsBroughtForward(_ folder: String?) {
        #expect(plan("com.mitchellh.ghostty", tty: "ttys003", folder: folder) == .activateApp)
    }

    @Test func noAppNoActivation() {
        #expect(plan(nil, tty: "ttys003", folder: "\(projects)/acme-api") == .none)
    }
}
