import Foundation
import Testing

@testable import HookMeUpCore

/// A file system with only the files it is given.
private struct Files: FileSystem {
    var files: [String: Data] = [:]

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        isDirectory?.pointee = false
        return files[path] != nil
    }

    func contents(atPath path: String) -> Data? { files[path] }
}

/// A generator that hands out the values it is given.
private struct FixedRandom: RandomNumberGenerator {
    var values: [UInt64]

    mutating func next() -> UInt64 { values.isEmpty ? 0 : values.removeFirst() }
}

private let home = "/Users/dev"

/// extensions.json as VS Code writes it, with an entry per id.
private func registry(_ ids: [String]) -> Data {
    let entries = ids.map {
        #"{"identifier": {"id": "\#($0)", "uuid": "4bd5d2c9-9d65-401a-b0b2-7498d9f17615"}, "version": "0.1.0", "#
            + #""relativeLocation": "\#($0)-0.1.0", "metadata": {"source": "vsix"}}"#
    }
    return Data(("[" + entries.joined(separator: ", ") + "]").utf8)
}

private let editors = [
    ("com.microsoft.VSCode", ".vscode", "VS Code", "code"),
    ("com.microsoft.VSCodeInsiders", ".vscode-insiders", "VS Code Insiders", "code-insiders"),
    ("com.todesktop.230313mzl4w4u92", ".cursor", "Cursor", "cursor"),
    ("com.exafunction.windsurf", ".windsurf", "Windsurf", "windsurf"),
]

/// The ancestors of a session in VS Code's integrated terminal, nearest first: Claude Code,
/// the terminal's shell, the pty host, a helper, VS Code itself.
private let ancestors: [Int32] = [4242, 4100, 3900, 3800, 3700]
private let editorPID: Int32 = 3700
private let nonce = "0123456789abcdef0123456789abcdef"
private let clickTime = Date(timeIntervalSince1970: 1_731_672_000.123_9)

@Suite struct EditorExtensionTests {
    @Test func theExtensionIsHookMeUpsOwn() {
        #expect(EditorExtension.identifier == "hook-me-up.hook-me-up")
        #expect(EditorExtension.requestFileName == "editor-focus-request.json")
    }

    /// The request sits next to the agent's socket, in its private support folder (where the
    /// extension looks for it).
    @Test func theRequestLivesInTheSupportFolder() {
        let home = URL(fileURLWithPath: "/Users/dev")
        let support = "/Users/dev/Library/Application Support/hook-me-up"
        #expect(HookMeUpPaths.supportFolder(home: home).path == support)
        #expect(HookMeUpPaths.socketURL(home: home).path == support + "/agent.sock")
        #expect(HookMeUpPaths.editorFocusRequestURL(home: home).path == support + "/editor-focus-request.json")
    }

    /// The same four editors whose windows `EditorWindows` reads, each with its extensions
    /// folder, name and command-line tool.
    @Test func eachVSCodeFamilyEditorHasItsExtensionsRegistry() {
        #expect(EditorExtension.editors.map(\.bundleID) == editors.map(\.0))
        for (bundleID, folder, name, cli) in editors {
            let editor = EditorExtension.editor(bundleID: bundleID)
            #expect(editor?.name == name)
            #expect(editor?.commandLineTool == cli)
            #expect(EditorWindows.tracksWindows(bundleID: bundleID))
            #expect(
                EditorExtension.registryPath(bundleID: bundleID, home: home)
                    == "\(home)/\(folder)/extensions/extensions.json")
            #expect(
                EditorExtension.registryPath(bundleID: bundleID, home: home + "/")
                    == "\(home)/\(folder)/extensions/extensions.json")
        }
    }

    @Test(arguments: ["dev.zed.Zed", "com.mitchellh.ghostty", "com.apple.Terminal", "org.example.app", ""])
    func otherAppsHaveNoRegistry(_ bundleID: String) {
        #expect(EditorExtension.editor(bundleID: bundleID) == nil)
        #expect(EditorExtension.registryPath(bundleID: bundleID, home: home) == nil)
    }

    @Test func aHomeThatIsNotAbsoluteHasNoRegistry() {
        #expect(EditorExtension.registryPath(bundleID: "com.microsoft.VSCode", home: "Users/dev") == nil)
        #expect(EditorExtension.registryPath(bundleID: "com.microsoft.VSCode", home: "") == nil)
    }

    @Test func aRegistryWithTheExtensionHasItInstalled() {
        #expect(EditorExtension.isInstalled(registry: registry(["hook-me-up.hook-me-up"])))
        #expect(EditorExtension.isInstalled(registry: registry(["ms-python.python", "Hook-Me-Up.HOOK-ME-UP"])))
    }

    @Test func aRegistryWithoutItDoesNotHaveIt() {
        #expect(!EditorExtension.isInstalled(registry: registry([])))
        #expect(!EditorExtension.isInstalled(registry: registry(["ms-python.python", "hook-me-up.other"])))
        #expect(!EditorExtension.isInstalled(registry: registry(["xhook-me-up.hook-me-up", "hook-me-up.hook-me-up2"])))
    }

    /// Entries without an id, or with one that isn't text, don't count; nor does anything
    /// that isn't a JSON array of entries.
    @Test(arguments: [
        #"[{"version": "0.1.0", "relativeLocation": "hook-me-up.hook-me-up-0.1.0"}]"#,
        #"[{"identifier": {"uuid": "hook-me-up.hook-me-up"}}]"#, #"[{"identifier": {"id": 42}}]"#,
        #"[{"identifier": "hook-me-up.hook-me-up"}]"#, #"["hook-me-up.hook-me-up"]"#,
        #"{"identifier": {"id": "hook-me-up.hook-me-up"}}"#, #"[{"identifier": {"id": "hook-me-up.hook-me-up"}"#, "",
        "not json",
    ])
    func malformedRegistriesDoNotHaveIt(_ text: String) {
        #expect(!EditorExtension.isInstalled(registry: Data(text.utf8)))
    }

    /// The registry is read through the file system, only up to `maxRegistryBytes`.
    @Test func theRegistryIsReadFromTheEditorsExtensionsFolder() {
        var disk = Files()
        disk.files["\(home)/.vscode/extensions/extensions.json"] = registry(["hook-me-up.hook-me-up"])
        disk.files["\(home)/.cursor/extensions/extensions.json"] = registry(["ms-python.python"])
        #expect(EditorExtension.isInstalled(bundleID: "com.microsoft.VSCode", home: home, fileSystem: disk))
        #expect(!EditorExtension.isInstalled(bundleID: "com.todesktop.230313mzl4w4u92", home: home, fileSystem: disk))
        #expect(!EditorExtension.isInstalled(bundleID: "com.exafunction.windsurf", home: home, fileSystem: disk))
        #expect(!EditorExtension.isInstalled(bundleID: "dev.zed.Zed", home: home, fileSystem: disk))
    }

    @Test func anOversizedRegistryIsNotRead() {
        var big = registry(["hook-me-up.hook-me-up"])
        big.append(Data(repeating: 0x20, count: EditorExtension.maxRegistryBytes))
        #expect(EditorExtension.isInstalled(registry: big))  // valid JSON, only too large to read
        let disk = Files(files: ["\(home)/.vscode/extensions/extensions.json": big])
        #expect(!EditorExtension.isInstalled(bundleID: "com.microsoft.VSCode", home: home, fileSystem: disk))
    }

    // MARK: The request

    /// Byte for byte: sorted keys, the click time in milliseconds, the pids from the
    /// session's process up to (not including) the editor's.
    @Test func theRequestNamesTheSessionsProcessesUpToTheEditor() throws {
        let data = try #require(
            EditorExtension.request(pids: ancestors, editorPID: editorPID, nonce: nonce, now: clickTime))
        #expect(
            String(decoding: data, as: UTF8.self)
                == #"{"created":1731672000123,"nonce":"0123456789abcdef0123456789abcdef","pids":[4242,4100,3900,3800],"version":1}"#
        )
        #expect(data.count <= EditorExtension.maxRequestBytes)
    }

    @Test func atMostSixteenPidsAreSent() throws {
        let many = (1...40).map { Int32(10_000 + $0) } + [editorPID]
        let data = try #require(EditorExtension.request(pids: many, editorPID: editorPID, nonce: nonce, now: clickTime))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["pids"] as? [Int] == (1...16).map { 10_000 + $0 })
        #expect(data.count <= EditorExtension.maxRequestBytes)
    }

    /// The editor must be one of the ancestors (that is how it was found), with at least one
    /// process before it; pids that aren't positive are never sent.
    @Test func withoutTheSessionsProcessesThereIsNoRequest() {
        #expect(EditorExtension.request(pids: ancestors, editorPID: 999, nonce: nonce, now: clickTime) == nil)
        #expect(
            EditorExtension.request(pids: [editorPID, 1], editorPID: editorPID, nonce: nonce, now: clickTime) == nil)
        #expect(EditorExtension.request(pids: [], editorPID: editorPID, nonce: nonce, now: clickTime) == nil)
        #expect(
            EditorExtension.request(pids: [0, -5, editorPID], editorPID: editorPID, nonce: nonce, now: clickTime) == nil
        )
        let mixed = EditorExtension.request(
            pids: [4242, 0, -1, 4100, editorPID], editorPID: editorPID, nonce: nonce, now: clickTime)
        #expect(mixed.map { String(decoding: $0, as: UTF8.self) }?.contains(#""pids":[4242,4100]"#) == true)
    }

    @Test(arguments: [
        "", "0123456789abcdef", "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef0123456789abcdeg",
        "0123456789abcdef0123456789abcdef0", "\"; rm -rf ~ #0123456789abcdef0123",
    ])
    func aMalformedNonceGivesNoRequest(_ nonce: String) {
        #expect(EditorExtension.request(pids: ancestors, editorPID: editorPID, nonce: nonce, now: clickTime) == nil)
        #expect(!EditorExtension.isValidNonce(nonce))
    }

    @Test func noncesAre32HexDigits() {
        var fixed = FixedRandom(values: [0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210])
        #expect(EditorExtension.makeNonce(using: &fixed) == "0123456789abcdeffedcba9876543210")
        var zero = FixedRandom(values: [])
        #expect(EditorExtension.makeNonce(using: &zero) == String(repeating: "0", count: 32))
        var system = SystemRandomNumberGenerator()
        let first = EditorExtension.makeNonce(using: &system)
        #expect(EditorExtension.isValidNonce(first))
        #expect(first != EditorExtension.makeNonce(using: &system))
    }

    // MARK: When to ask

    private func ask(
        _ plan: SessionActivation, bundleID: String = "com.microsoft.VSCode", alive: Bool = true, windows: Int = 1,
        installed: Bool = true
    ) -> Bool {
        EditorExtension.shouldAsk(
            plan: plan, bundleID: bundleID, sessionAlive: alive, openWindowCount: { windows },
            isInstalled: { installed })
    }

    /// A VS Code-family editor with the extension, the session running and a window open:
    /// asked when its window is focused, and when the editor is only brought forward (the
    /// terminal may be in the window that comes forward).
    @Test(arguments: editors.map(\.0))
    func theEditorIsAskedWhenItsWindowIsFocusedOrItComesForward(_ bundleID: String) {
        #expect(ask(.focusWindow("/Users/dev/projects/acme-api"), bundleID: bundleID))
        #expect(ask(.activateApp, bundleID: bundleID))
    }

    @Test func notAskedWithoutTheExtensionASessionOrAWindow() {
        #expect(!ask(.focusWindow("/Users/dev/projects/acme-api"), installed: false))
        #expect(!ask(.activateApp, installed: false))
        #expect(!ask(.focusWindow("/Users/dev/projects/acme-api"), alive: false))
        #expect(!ask(.activateApp, alive: false))
        #expect(!ask(.activateApp, windows: 0))
    }

    /// Terminals, Zed and other apps are never asked, and nothing is read for them.
    @Test func otherAppsAndPlansAreNeverAsked() {
        #expect(!ask(.activateApp, bundleID: "dev.zed.Zed"))
        #expect(!ask(.activateApp, bundleID: "com.mitchellh.ghostty"))
        #expect(!ask(.selectTab(.appleTerminal, tty: "ttys003")))
        #expect(!ask(.focusTerminalByFolder(.ghostty, folder: "/Users/dev", tty: "/dev/ttys003")))
        #expect(!ask(.focusHerdrTerminal(id: "test-pane_1")))
        #expect(!ask(.none))
        var looked = false
        let asked = EditorExtension.shouldAsk(
            plan: .activateApp, bundleID: "dev.zed.Zed", sessionAlive: true,
            openWindowCount: {
                looked = true
                return 1
            },
            isInstalled: {
                looked = true
                return true
            })
        #expect(!asked)
        #expect(!looked)
    }
}
