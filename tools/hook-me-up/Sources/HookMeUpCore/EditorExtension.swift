import Foundation

/// Hook Me Up's extension for VS Code, VS Code Insiders, Cursor and Windsurf (the same
/// editors `EditorWindows` reads), which shows a session's integrated terminal when its
/// notification is clicked. The agent can't reach into an editor, so it writes a request
/// file (`requestFileName`, in its support folder); every editor window's extension
/// watches that file and the one with a terminal whose process is one of the request's
/// pids shows it. Nothing else is in the request: no path, no title, no command.
///
/// Whether the extension is installed comes from the editor's extensions registry
/// (`extensions.json` in its extensions folder), read with a size cap. A disabled
/// extension still counts as installed (that state is kept elsewhere): its request then
/// goes unanswered, and the click works as without it.
public enum EditorExtension {
    /// The extension's identifier: publisher "hook-me-up", name "hook-me-up".
    public static let identifier = "hook-me-up.hook-me-up"
    /// The extension's package, in the app's `Contents/Resources` (built by
    /// scripts/build-vsix.sh; install.sh hands it to each editor's command-line tool).
    public static let packageName = "hook-me-up.vsix"
    /// The request file, in the agent's support folder (`HookMeUpPaths.supportFolder`).
    public static let requestFileName = "editor-focus-request.json"
    /// The extensions registry is read only up to this size.
    public static let maxRegistryBytes = 4 << 20
    /// At most this many pids go into a request (the extension refuses more).
    public static let maxPIDs = 16
    /// The largest request the extension reads.
    public static let maxRequestBytes = 4096

    /// A VS Code-family editor.
    public struct Editor: Equatable, Sendable {
        /// Its bundle identifier.
        public let bundleID: String
        /// How it is called in messages.
        public let name: String
        /// The folder in the home folder that holds its `extensions` folder.
        public let dataFolder: String
        /// Its command-line tool, which installs extensions (`--install-extension`).
        public let commandLineTool: String
    }

    /// The editors, in the order messages list them.
    public static let editors = [
        Editor(bundleID: "com.microsoft.VSCode", name: "VS Code", dataFolder: ".vscode", commandLineTool: "code"),
        Editor(
            bundleID: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders", dataFolder: ".vscode-insiders",
            commandLineTool: "code-insiders"),
        Editor(
            bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", dataFolder: ".cursor",
            commandLineTool: "cursor"),
        Editor(
            bundleID: "com.exafunction.windsurf", name: "Windsurf", dataFolder: ".windsurf",
            commandLineTool: "windsurf"),
    ]

    /// The editor with `bundleID`, if it is one of `editors`.
    public static func editor(bundleID: String) -> Editor? {
        editors.first { $0.bundleID == bundleID }
    }

    /// The editor's extensions folder for the user whose home folder is `home` (absolute).
    public static func extensionsFolder(of editor: Editor, home: String) -> String? {
        guard home.hasPrefix("/") else { return nil }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return "\(base)/\(editor.dataFolder)/extensions"
    }

    /// The editor's extensions registry, or nil for an app that isn't one of `editors`.
    public static func registryPath(bundleID: String, home: String) -> String? {
        guard let editor = editor(bundleID: bundleID), let folder = extensionsFolder(of: editor, home: home) else {
            return nil
        }
        return folder + "/extensions.json"
    }

    /// Whether `registry` (an editor's extensions.json: an array of entries with
    /// `identifier.id`) lists the extension; ids compare ignoring case, as the editors do.
    /// Anything else (not JSON, not an array, entries without a text id) lists nothing.
    public static func isInstalled(registry: Data) -> Bool {
        guard let entries = (try? JSONSerialization.jsonObject(with: registry)) as? [Any] else { return false }
        let wanted = identifier.lowercased()
        return entries.contains { entry in
            let id = ((entry as? [String: Any])?["identifier"] as? [String: Any])?["id"] as? String
            return id?.lowercased() == wanted
        }
    }

    /// Whether the editor with `bundleID` has the extension in its registry under `home`.
    public static func isInstalled(bundleID: String, home: String, fileSystem: some FileSystem) -> Bool {
        guard let path = registryPath(bundleID: bundleID, home: home),
            let data = fileSystem.contents(atPath: path, limit: maxRegistryBytes)
        else { return false }
        return isInstalled(registry: data)
    }

    /// Whether a click should ask the editor's extension to show the session's terminal:
    /// for one of `editors`, when its window is focused (`.focusWindow`) or it is only
    /// brought forward (`.activateApp`: the terminal may be in the window that comes
    /// forward, and only a window with a terminal of the session's processes acts), while
    /// the session's process runs (so its pids are still its own), the editor has a window
    /// open and the extension is installed. The last two are asked only when needed.
    public static func shouldAsk(
        plan: SessionActivation, bundleID: String, sessionAlive: Bool, openWindowCount: () -> Int,
        isInstalled: () -> Bool
    ) -> Bool {
        switch plan {
        case .focusWindow, .activateApp: break
        case .selectTab, .focusTerminalByFolder, .focusHerdrTerminal, .none: return false
        }
        guard editor(bundleID: bundleID) != nil, sessionAlive else { return false }
        return openWindowCount() > 0 && isInstalled()
    }

    /// The request for a click: JSON with sorted keys (`created`: the click time in
    /// milliseconds since 1970; `nonce`; `pids`: the session's processes from the nearest,
    /// up to and without the editor's own `editorPID`, at most `maxPIDs`; `version` 1).
    /// Nil when `nonce` isn't one of `makeNonce`'s, the editor isn't among `pids`, or no
    /// process comes before it.
    public static func request(pids: [Int32], editorPID: Int32, nonce: String, now: Date) -> Data? {
        guard isValidNonce(nonce), let editorIndex = pids.firstIndex(of: editorPID) else { return nil }
        let session = Array(pids[..<editorIndex].filter { $0 > 0 }.prefix(maxPIDs))
        guard !session.isEmpty else { return nil }
        let request = Request(
            created: Int64((now.timeIntervalSince1970 * 1000).rounded(.down)), nonce: nonce, pids: session, version: 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(request)
    }

    /// A fresh request id: 32 lowercase hexadecimal digits from `generator`.
    public static func makeNonce(using generator: inout some RandomNumberGenerator) -> String {
        (0..<2).map { _ in
            let digits = String(generator.next(), radix: 16)
            return String(repeating: "0", count: 16 - digits.count) + digits
        }.joined()
    }

    /// Whether `nonce` has `makeNonce`'s form exactly.
    public static func isValidNonce(_ nonce: String) -> Bool {
        let scalars = Array(nonce.unicodeScalars)
        return scalars.count == 32 && scalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private struct Request: Encodable {
        let created: Int64
        let nonce: String
        let pids: [Int32]
        let version: Int
    }
}
