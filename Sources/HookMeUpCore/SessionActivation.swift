import Foundation

/// How to bring a session forward, decided from the app that runs it.
public enum SessionActivation: Equatable, Sendable {
    /// Terminal or iTerm2: select the tab with this tty (AppleScript), then bring the app
    /// forward.
    case selectTab(TerminalApp, tty: String)
    /// An editor (VS Code, Cursor, Windsurf, Zed): open the session's folder with it, which
    /// focuses the window that has that folder open (or opens one).
    case openFolder(String)
    /// Any other app: bring it forward.
    case activateApp
    /// No app was found in the session's process tree.
    case none

    /// The strategy for a session whose app has `ownerBundleID`, with controlling terminal
    /// `tty` and project `folder`. A folder is used only when it is an existing absolute
    /// directory (checked through `fileSystem`).
    public static func plan(
        ownerBundleID: String?, tty: String?, folder: String?, fileSystem: some FileSystem
    ) -> SessionActivation {
        guard let ownerBundleID else { return .none }
        let app = TerminalApp(bundleID: ownerBundleID)
        if let app, app.selectsTabByTTY, let tty, TerminalScripts.selectTab(app, tty: tty) != nil {
            return .selectTab(app, tty: tty)
        }
        if let app, app.opensFolders, let folder = existingFolder(folder, fileSystem: fileSystem) {
            return .openFolder(folder)
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
