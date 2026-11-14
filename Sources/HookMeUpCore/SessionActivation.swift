import Foundation

/// How to bring a session forward, decided from the app that runs it.
public enum SessionActivation: Equatable, Sendable {
    /// Terminal or iTerm2: select the tab with this tty (AppleScript), then bring the app
    /// forward.
    case selectTab(TerminalApp, tty: String)
    /// VS Code, VS Code Insiders, Cursor or Windsurf with a window open that holds the
    /// session's folder: open exactly that window's folder (or `.code-workspace` file) with
    /// the editor, which focuses that window.
    case focusWindow(String)
    /// Any other app: bring it forward.
    case activateApp
    /// No app was found in the session's process tree.
    case none

    /// The strategy for a session whose app has `ownerBundleID`, with controlling terminal
    /// `tty` and project `folder`. A folder is used only when it is an existing absolute
    /// directory (checked through `fileSystem`). An editor's open windows come from its
    /// storage.json under `home` (size-capped); `resolve` resolves symbolic links. When no
    /// open window holds the folder, or the window state can't be read, the editor is only
    /// brought forward: a click never opens a new window.
    public static func plan(
        ownerBundleID: String?, tty: String?, folder: String?, home: String, fileSystem: some FileSystem,
        resolve: (String) -> String = { $0 }
    ) -> SessionActivation {
        guard let ownerBundleID else { return .none }
        if let app = TerminalApp(bundleID: ownerBundleID), app.selectsTabByTTY, let tty,
            TerminalScripts.selectTab(app, tty: tty) != nil
        {
            return .selectTab(app, tty: tty)
        }
        if let storage = EditorWindows.storagePath(bundleID: ownerBundleID, home: home),
            let folder = existingFolder(folder, fileSystem: fileSystem),
            let data = fileSystem.contents(atPath: storage, limit: EditorWindows.maxStorageBytes),
            let window = EditorWindows.best(
                for: folder, among: EditorWindows.windows(storage: data, fileSystem: fileSystem), resolve: resolve)
        {
            return .focusWindow(window.target)
        }
        return .activateApp
    }

    /// `path`, normalised, when it is an existing absolute directory.
    static func existingFolder(_ path: String?, fileSystem: some FileSystem) -> String? {
        guard let path, path.hasPrefix("/") else { return nil }
        let normalised = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileSystem.fileExists(atPath: normalised, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return normalised
    }
}
