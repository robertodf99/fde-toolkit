import Foundation

/// An open window of VS Code or an editor built on it.
public struct EditorWindow: Equatable, Sendable {
    /// What to open to focus the window, exactly as the editor recorded it: the folder the
    /// window has open, or its `.code-workspace` file.
    public let target: String
    /// The folders the window shows: its folder, or the workspace's folders.
    public let roots: [String]

    /// A window opened on `target` that shows `roots`.
    public init(target: String, roots: [String]) {
        self.target = target
        self.roots = roots
    }
}

/// The open windows of VS Code, VS Code Insiders, Cursor and Windsurf, from the window state
/// each editor keeps in `storage.json` (`windowsState`), and the one that holds a session's
/// folder. Opening exactly a window's folder (or workspace file) with the editor focuses that
/// window; any other folder would open a new one.
public enum EditorWindows {
    /// storage.json is read only up to this size.
    public static let maxStorageBytes = 8 << 20
    /// A `.code-workspace` file is read only up to this size.
    public static let maxWorkspaceBytes = 1 << 20
    /// At most this many recorded windows are looked at (each workspace window reads a file).
    public static let maxWindows = 64

    /// The folder under Application Support where each editor keeps its state.
    private static let stateFolders = [
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
    ]

    /// Whether the app with `bundleID` keeps a window state that can be read.
    public static func tracksWindows(bundleID: String) -> Bool { stateFolders[bundleID] != nil }

    /// The editor's storage.json for the user whose home folder is `home` (absolute), or nil
    /// when the app keeps no window state that can be read.
    public static func storagePath(bundleID: String, home: String) -> String? {
        guard home.hasPrefix("/"), let folder = stateFolders[bundleID] else { return nil }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return "\(base)/Library/Application Support/\(folder)/User/globalStorage/storage.json"
    }

    /// The windows recorded in storage.json, the last active one first: local folders that
    /// exist, and workspaces whose `.code-workspace` file can be read. Anything else (remote,
    /// untitled or empty windows, unreadable entries) is left out; nothing comes back when
    /// `storage` is not JSON.
    public static func windows(storage: Data, fileSystem: some FileSystem) -> [EditorWindow] {
        guard let state = (try? JSONDecoder().decode(StorageFile.self, from: storage))?.windowsState else { return [] }
        var entries = state.lastActiveWindow.map { [$0] } ?? []
        entries += state.openedWindows ?? []
        var windows: [EditorWindow] = []
        for entry in entries.prefix(maxWindows) {
            guard let window = window(entry, fileSystem: fileSystem),
                !windows.contains(where: { $0.target == window.target })
            else { continue }
            windows.append(window)
        }
        return windows
    }

    /// The window that holds `folder` (absolute): one open on the folder itself; else the one
    /// whose folder is the closest enclosing folder (a worktree or subfolder of its project);
    /// else, as a last resort, the one whose folder is closest inside it. Ties go to the
    /// earlier window. Paths are compared by components after `resolve` (symbolic links) and
    /// normalisation (`.`, `..`, trailing slashes, the `/private` prefix of /var, /tmp, /etc).
    public static func best(
        for folder: String, among windows: [EditorWindow], resolve: (String) -> String = { $0 }
    ) -> EditorWindow? {
        guard folder.hasPrefix("/") else { return nil }
        let session = components(resolve(folder))
        var best: (window: EditorWindow, rank: Rank)?
        for window in windows {
            for root in window.roots where root.hasPrefix("/") {
                guard let rank = rank(of: components(resolve(root)), for: session) else { continue }
                if let current = best, current.rank >= rank { continue }
                best = (window, rank)
            }
        }
        return best?.window
    }

    // MARK: Matching

    /// How well a window's folder fits the session's folder; higher is better.
    private struct Rank: Comparable {
        let tier: Int
        let closeness: Int

        static func < (lhs: Rank, rhs: Rank) -> Bool { (lhs.tier, lhs.closeness) < (rhs.tier, rhs.closeness) }
    }

    private static func rank(of root: [Substring], for session: [Substring]) -> Rank? {
        if root == session { return Rank(tier: 3, closeness: 0) }
        if root.count < session.count, Array(session.prefix(root.count)) == root {
            return Rank(tier: 2, closeness: root.count)  // the deeper the enclosing folder, the better
        }
        if session.count < root.count, Array(root.prefix(session.count)) == session {
            return Rank(tier: 1, closeness: -root.count)  // the shallower the folder inside, the better
        }
        return nil
    }

    /// The components of an absolute path without `.`, `..` or empty ones, and without the
    /// `/private` prefix of /var, /tmp and /etc.
    static func components(_ path: String) -> [Substring] {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        if parts.count >= 2, parts[0] == "private", ["var", "tmp", "etc"].contains(parts[1]) {
            parts.removeFirst()
        }
        return parts
    }

    static func normalised(_ path: String) -> String { "/" + components(path).joined(separator: "/") }

    // MARK: Reading

    private static func window(_ entry: WindowEntry, fileSystem: some FileSystem) -> EditorWindow? {
        if let uri = entry.folder {
            guard let folder = localPath(uri) else { return nil }
            var isDirectory: ObjCBool = false
            guard fileSystem.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return EditorWindow(target: folder, roots: [folder])
        }
        // Untitled workspaces keep a workspace.json that would open as a file: only named ones.
        guard let uri = entry.configPath, let file = localPath(uri), file.hasSuffix(".code-workspace"),
            let roots = workspaceFolders(file, fileSystem: fileSystem), !roots.isEmpty
        else { return nil }
        return EditorWindow(target: file, roots: roots)
    }

    /// The folders of a `.code-workspace` file (JSON with comments and trailing commas); a
    /// relative `path` is relative to the file's folder.
    private static func workspaceFolders(_ file: String, fileSystem: some FileSystem) -> [String]? {
        guard let data = fileSystem.contents(atPath: file, limit: maxWorkspaceBytes) else { return nil }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        guard let workspace = try? decoder.decode(WorkspaceFile.self, from: data) else { return nil }
        let base = (file as NSString).deletingLastPathComponent
        return workspace.folders.compactMap { folder in
            if let path = folder.path, !path.isEmpty {
                return normalised(path.hasPrefix("/") ? path : base + "/" + path)
            }
            return folder.uri.flatMap(localPath).map(normalised)
        }
    }

    /// The path of a local `file:` URI (percent-decoded); nil for anything else.
    static func localPath(_ uri: String) -> String? {
        guard let url = URL(string: uri), url.scheme?.lowercased() == "file" else { return nil }
        let host = url.host ?? ""
        guard host.isEmpty || host == "localhost" else { return nil }
        let path = url.path
        return path.hasPrefix("/") ? path : nil
    }
}

// MARK: storage.json and .code-workspace, decoded leniently: a malformed entry is skipped.

private struct StorageFile: Decodable {
    let windowsState: WindowsState?

    private enum CodingKeys: String, CodingKey { case windowsState }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        windowsState = try? container?.decodeIfPresent(WindowsState.self, forKey: .windowsState)
    }
}

private struct WindowsState: Decodable {
    let lastActiveWindow: WindowEntry?
    let openedWindows: [WindowEntry]?

    private enum CodingKeys: String, CodingKey { case lastActiveWindow, openedWindows }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastActiveWindow = try? container.decodeIfPresent(WindowEntry.self, forKey: .lastActiveWindow)
        openedWindows = try? container.decodeIfPresent([WindowEntry].self, forKey: .openedWindows)
    }
}

/// A recorded window: `folder` is a URI; a workspace window has its file's URI in
/// `workspaceIdentifier.configURIPath` (what VS Code writes), or `workspace.configPath`.
private struct WindowEntry: Decodable {
    let folder: String?
    let configPath: String?

    private enum CodingKeys: String, CodingKey { case folder, workspaceIdentifier, workspace }
    private enum WorkspaceKeys: String, CodingKey { case configURIPath, configPath }

    init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        folder = try? container?.decodeIfPresent(String.self, forKey: .folder)
        let identifier = try? container?.nestedContainer(keyedBy: WorkspaceKeys.self, forKey: .workspaceIdentifier)
        let workspace = try? container?.nestedContainer(keyedBy: WorkspaceKeys.self, forKey: .workspace)
        configPath =
            (try? identifier?.decodeIfPresent(String.self, forKey: .configURIPath))
            ?? (try? workspace?.decodeIfPresent(String.self, forKey: .configPath))
    }
}

private struct WorkspaceFile: Decodable {
    let folders: [WorkspaceFolder]
}

/// A workspace folder: a `path` (absolute or relative to the file) or a `uri`.
private struct WorkspaceFolder: Decodable {
    let path: String?
    let uri: String?

    private enum CodingKeys: String, CodingKey { case path, uri }

    init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        path = try? container?.decodeIfPresent(String.self, forKey: .path)
        uri = try? container?.decodeIfPresent(String.self, forKey: .uri)
    }
}
