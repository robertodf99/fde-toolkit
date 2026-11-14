import Foundation
import Testing

@testable import HookMeUpCore

/// A file system with only the folders and files it is given.
private struct FakeDisk: FileSystem {
    var folders: Set<String> = []
    var files: [String: String] = [:]

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let folder = folders.contains(path)
        isDirectory?.pointee = ObjCBool(folder)
        return folder || files[path] != nil
    }

    func contents(atPath path: String) -> Data? { files[path].map { Data($0.utf8) } }
}

/// A file system that counts the reads of each file.
private final class CountingDisk: FileSystem {
    let disk: FakeDisk
    private(set) var reads: [String: Int] = [:]

    init(_ disk: FakeDisk) { self.disk = disk }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        disk.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func contents(atPath path: String) -> Data? {
        reads[path, default: 0] += 1
        return disk.contents(atPath: path)
    }
}

/// A storage.json whose window state has `lastActive` and `opened` (JSON objects, as text).
private func storage(lastActive: String? = nil, opened: [String] = []) -> Data {
    var members: [String] = []
    if let lastActive { members.append(#""lastActiveWindow": \#(lastActive)"#) }
    members.append(#""openedWindows": [\#(opened.joined(separator: ", "))]"#)
    let text = #"{"telemetry.machineId": "x", "windowsState": {\#(members.joined(separator: ", "))}, "theme": "dark"}"#
    return Data(text.utf8)
}

private func folderEntry(_ uri: String) -> String {
    #"{"folder": "\#(uri)", "backupPath": "/b", "uiState": {"mode": 1, "width": 800}}"#
}

/// A workspace window as VS Code records it (`workspaceIdentifier.configURIPath`).
private func workspaceEntry(_ uri: String) -> String {
    #"{"workspaceIdentifier": {"id": "abc", "configURIPath": "\#(uri)"}, "uiState": {"mode": 1}}"#
}

private func window(_ roots: String...) -> EditorWindow { EditorWindow(target: roots[0], roots: roots) }

private func best(_ folder: String, _ windows: [EditorWindow], resolve: (String) -> String = { $0 }) -> String? {
    EditorWindows.best(for: folder, among: windows, resolve: resolve)?.target
}

@Suite struct EditorWindowsTests {
    // MARK: Where each editor keeps its window state

    @Test(arguments: [
        ("com.microsoft.VSCode", "Code"), ("com.microsoft.VSCodeInsiders", "Code - Insiders"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"), ("com.exafunction.windsurf", "Windsurf"),
    ])
    func storageOfEachEditor(_ bundleID: String, _ folder: String) {
        #expect(
            EditorWindows.storagePath(bundleID: bundleID, home: "/Users/dev")
                == "/Users/dev/Library/Application Support/\(folder)/User/globalStorage/storage.json")
    }

    @Test(arguments: ["dev.zed.Zed", "com.apple.Terminal", "com.anthropic.claudefordesktop", "org.example.app"])
    func otherAppsHaveNoWindowState(_ bundleID: String) {
        #expect(EditorWindows.storagePath(bundleID: bundleID, home: "/Users/dev") == nil)
    }

    @Test(arguments: ["", "Users/dev"])
    func aRelativeHomeHasNoWindowState(_ home: String) {
        #expect(EditorWindows.storagePath(bundleID: "com.microsoft.VSCode", home: home) == nil)
    }

    // MARK: Reading storage.json

    @Test func readsTheOpenWindowsLastActiveFirst() {
        let disk = FakeDisk(folders: ["/Users/dev/acme-api", "/Users/dev/my repo", "/Users/dev/café"])
        let data = storage(
            lastActive: folderEntry("file:///Users/dev/my%20repo"),
            opened: [
                folderEntry("file:///Users/dev/acme-api"), folderEntry("file:///Users/dev/my%20repo"),
                folderEntry("file:///Users/dev/caf%C3%A9/"),
            ])
        #expect(
            EditorWindows.windows(storage: data, fileSystem: disk) == [
                window("/Users/dev/my repo"), window("/Users/dev/acme-api"), window("/Users/dev/café"),
            ])
    }

    /// Remote, untitled or unreadable windows, and folders that are gone, are left out: opening
    /// them could create a window instead of focusing one.
    @Test func unusableWindowsAreLeftOut() {
        let disk = FakeDisk(
            folders: [
                "/Users/dev/acme-api", "/home/dev/acme-api", "/share/acme-api",
                "/Users/dev/Library/Application Support/Code/Workspaces/1",
            ],
            files: [
                "/Users/dev/Library/Application Support/Code/Workspaces/1/workspace.json":
                    #"{"folders": [{"path": "/Users/dev/acme-api"}]}"#,
                "/Users/dev/notes.txt": "notes",
                "/Users/dev/acme.code-workspace": #"{"folders": [{"path": "/Users/dev/acme-api"}]}"#,
            ])
        let data = storage(
            lastActive: folderEntry("vscode-remote://ssh-remote%2Bbox/home/dev/acme-api"),
            opened: [
                folderEntry("file:///Users/dev/gone"),
                folderEntry("file:///Users/dev/notes.txt"),
                folderEntry("file://fileserver/share/acme-api"),
                folderEntry("vscode-vfs:/home/dev/acme-api"),
                folderEntry("acme-api"),
                #"{"folder": 42}"#,
                #""a string""#,
                #"{"workspace": {"id": "1"}}"#,
                #"{"workspaceIdentifier": {"id": "1", "configURIPath": 7}}"#,
                #"{"workspace": {"id": "2", "configPath": "file:///Users/dev/acme.code-workspace"}}"#,
                workspaceEntry("file:///Users/dev/Library/Application%20Support/Code/Workspaces/1/workspace.json"),
                workspaceEntry("file:///Users/dev/missing.code-workspace"),
                #"{"emptyWindow": "1234"}"#,
                folderEntry("file:///Users/dev/acme-api"),
            ])
        #expect(EditorWindows.windows(storage: data, fileSystem: disk) == [window("/Users/dev/acme-api")])
    }

    @Test func onlyTheFirstWindowsAreLookedAt() {
        let folders = (1...(EditorWindows.maxWindows + 6)).map { "/Users/dev/p\($0)" }
        let data = storage(opened: folders.map { folderEntry("file://" + $0) })
        let windows = EditorWindows.windows(storage: data, fileSystem: FakeDisk(folders: Set(folders)))
        #expect(windows.map(\.target) == Array(folders.prefix(EditorWindows.maxWindows)))
    }

    @Test(arguments: [
        "", "not json", "[]", "{}", #"{"windowsState": 3}"#, #"{"windowsState": {"openedWindows": "x"}}"#,
        #"{"windowsState": {"lastActiveWindow": [], "openedWindows": [{"folder": "file:///Users/dev/acme-api""#,
    ])
    func malformedStorageHasNoWindows(_ text: String) {
        let disk = FakeDisk(folders: ["/Users/dev/acme-api"])
        #expect(EditorWindows.windows(storage: Data(text.utf8), fileSystem: disk).isEmpty)
    }

    /// A workspace window lists the workspace's folders (relative paths resolve against the
    /// file's folder; comments and trailing commas are allowed) and is opened by its file.
    @Test func aWorkspaceWindowHoldsItsFolders() {
        let file = "/Users/dev/acme/acme.code-workspace"
        let disk = FakeDisk(
            folders: ["/Users/dev/acme"],
            files: [
                file: """
                {
                    // The services.
                    "folders": [
                        { "path": "api" },
                        { "name": "Web", "path": "../acme-web/" },
                        { "path": "/srv/shared" },
                        { "uri": "file:///opt/acme%20tools" },
                        { "uri": "vscode-remote://ssh-remote%2Bbox/home/dev" },
                        { "path": 3 },
                    ],
                    "settings": {},
                }
                """
            ])
        let roots = ["/Users/dev/acme/api", "/Users/dev/acme-web", "/srv/shared", "/opt/acme tools"]
        let data = storage(lastActive: workspaceEntry("file:///Users/dev/acme/acme.code-workspace"))
        #expect(EditorWindows.windows(storage: data, fileSystem: disk) == [EditorWindow(target: file, roots: roots)])
    }

    /// Each recorded window is read once: VS Code lists the last active window twice.
    @Test func eachWorkspaceFileIsReadOnce() {
        let file = "/Users/dev/acme.code-workspace"
        let disk = CountingDisk(FakeDisk(files: [file: #"{"folders": [{"path": "/srv/acme"}]}"#]))
        let entry = workspaceEntry("file://" + file)
        let data = storage(lastActive: entry, opened: [entry, folderEntry("file:///srv/other"), entry])
        #expect(
            EditorWindows.windows(storage: data, fileSystem: disk) == [EditorWindow(target: file, roots: ["/srv/acme"])]
        )
        #expect(disk.reads == [file: 1])
    }

    @Test(arguments: ["not json", #"{"folders": 3}"#, #"{"folders": []}"#, #"{"settings": {}}"#])
    func aWorkspaceWithoutFoldersIsLeftOut(_ text: String) {
        let file = "/Users/dev/acme.code-workspace"
        let disk = FakeDisk(files: [file: text])
        #expect(
            EditorWindows.windows(storage: storage(lastActive: workspaceEntry("file://" + file)), fileSystem: disk)
                .isEmpty)
    }

    @Test func anOversizedWorkspaceIsNotRead() {
        let file = "/Users/dev/acme.code-workspace"
        let padding = String(repeating: " ", count: EditorWindows.maxWorkspaceBytes)
        let disk = FakeDisk(files: [file: #"{"folders": [{"path": "/srv/acme"}]}"# + padding])
        #expect(
            EditorWindows.windows(storage: storage(lastActive: workspaceEntry("file://" + file)), fileSystem: disk)
                .isEmpty)
    }

    // MARK: Choosing the window

    @Test func theWindowOfTheFolderItselfWins() {
        let windows = [window("/Users/dev/acme"), window("/Users/dev/acme/api"), window("/Users/dev/acme/api/src")]
        #expect(best("/Users/dev/acme/api", windows) == "/Users/dev/acme/api")
    }

    /// A worktree or a subfolder belongs to the window that has its repository open.
    @Test(arguments: [".worktrees/feature-login", ".claude/worktrees/feature-login", "packages/api/src"])
    func aFolderInsideAWindowBelongsToIt(_ inside: String) {
        let windows = [window("/Users/dev/other"), window("/Users/dev/acme")]
        #expect(best("/Users/dev/acme/" + inside, windows) == "/Users/dev/acme")
    }

    @Test func theClosestEnclosingWindowWins() {
        let windows = [window("/Users/dev"), window("/Users/dev/acme"), window("/Users/dev/acme/packages")]
        #expect(best("/Users/dev/acme/packages/api/.worktrees/x", windows) == "/Users/dev/acme/packages")
        #expect(best("/Users/dev/acme/docs", windows) == "/Users/dev/acme")
    }

    /// Last resort: a window open on a folder inside the session's folder (the closest one).
    @Test func aWindowInsideTheFolderIsTheLastResort() {
        let inside = [window("/Users/dev/acme/packages/api/src"), window("/Users/dev/acme/packages/api")]
        #expect(best("/Users/dev/acme", inside) == "/Users/dev/acme/packages/api")
        #expect(best("/Users/dev/acme", inside + [window("/Users/dev")]) == "/Users/dev")
    }

    /// Paths are compared by whole components.
    @Test func aSimilarNameIsNotAMatch() {
        #expect(best("/Users/dev/acme-api", [window("/Users/dev/acme"), window("/Users/dev/acme-web")]) == nil)
        #expect(best("/Users/dev/acme", [window("/Users/dev/acme-api")]) == nil)
        #expect(best("/Users/dev/acme-api/src", [window("/Users/dev/acme")]) == nil)
        #expect(best("/Users/dev/acme", [window("/Users/dev/acme-api/src")]) == nil)
    }

    /// macOS folders are case-insensitive by default: when nothing matches with the exact
    /// case, the same rules apply ignoring case.
    @Test func caseIsIgnoredAsTheLastTier() {
        #expect(best("/Users/dev/Acme/.worktrees/x", [window("/users/dev/acme")]) == "/users/dev/acme")
        #expect(best("/users/dev/acme", [window("/Users/Dev/ACME")]) == "/Users/Dev/ACME")
        #expect(best("/Users/dev/acme", [window("/Users/dev/ACME/api")]) == "/Users/dev/ACME/api")
        // Any match with the exact case comes first, even a weaker one.
        let windows = [window("/users/dev/acme/api"), window("/Users/dev/acme")]
        #expect(best("/Users/dev/acme/api", windows) == "/Users/dev/acme")
        #expect(best("/Users/dev/acme-api", [window("/users/dev/ACME")]) == nil)
    }

    @Test func noWindowNoMatch() {
        #expect(best("/Users/dev/acme", []) == nil)
        #expect(best("/Users/dev/acme", [window("/Users/dev/other"), window("/srv/acme")]) == nil)
    }

    @Test func aWorkspaceWindowMatchesThroughAnyOfItsFolders() {
        let workspace = EditorWindow(
            target: "/Users/dev/acme.code-workspace", roots: ["/Users/dev/acme-web", "/Users/dev/acme-api"])
        let windows = [window("/Users/dev"), workspace]
        #expect(best("/Users/dev/acme-api/.claude/worktrees/x", windows) == "/Users/dev/acme.code-workspace")
        #expect(best("/Users/dev/acme-web", windows) == "/Users/dev/acme.code-workspace")
        #expect(best("/Users/dev/notes", windows) == "/Users/dev")
    }

    /// With equally good windows, the earlier one (the last active window comes first) wins.
    @Test func tiesGoToTheEarlierWindow() {
        let windows = [
            EditorWindow(target: "/Users/dev/a.code-workspace", roots: ["/Users/dev/acme"]), window("/Users/dev/acme"),
        ]
        #expect(best("/Users/dev/acme/api", windows) == "/Users/dev/a.code-workspace")
    }

    /// `/private/var`, `/private/tmp` and `/private/etc` are the same folders as `/var`, `/tmp`
    /// and `/etc`; `.`, `..` and trailing slashes don't matter. The window's own path is opened.
    @Test func pathsAreNormalised() {
        #expect(
            best("/private/var/folders/xy/T/acme/.worktrees/x", [window("/var/folders/xy/T/acme")])
                == "/var/folders/xy/T/acme")
        #expect(best("/tmp/acme", [window("/private/tmp/acme/")]) == "/private/tmp/acme/")
        #expect(best("/Users/dev/./acme/api/../web/", [window("/Users/dev/acme/web")]) == "/Users/dev/acme/web")
        #expect(best("/privateer/var/acme", [window("/var/acme")]) == nil)
    }

    /// Symbolic links are resolved through the injected resolver, on both sides.
    @Test func symbolicLinksAreResolved() {
        let links = ["/Users/dev/work": "/Volumes/Work/projects", "/Users/dev/acme-link": "/Users/dev/acme"]
        let resolve = { (path: String) -> String in
            for (link, target) in links where path == link || path.hasPrefix(link + "/") {
                return target + path.dropFirst(link.count)
            }
            return path
        }
        #expect(
            best("/Users/dev/work/acme/.worktrees/x", [window("/Volumes/Work/projects/acme")], resolve: resolve)
                == "/Volumes/Work/projects/acme")
        #expect(
            best("/Users/dev/acme/api", [window("/Users/dev/acme-link")], resolve: resolve) == "/Users/dev/acme-link")
        #expect(best("/Users/dev/acme/api", [window("/Users/dev/acme-link")]) == nil)
    }
}
