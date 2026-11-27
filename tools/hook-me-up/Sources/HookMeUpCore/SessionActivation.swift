import Foundation

/// How to bring a session forward, decided from the app that runs it.
public enum SessionActivation: Equatable, Sendable {
    /// Terminal or iTerm2: select the tab with this tty (AppleScript), then bring the app
    /// forward.
    case selectTab(TerminalApp, tty: String)
    /// Ghostty: focus the one terminal whose working directory is this folder (an existing
    /// absolute folder; AppleScript, see `GhosttyTerminals`), else bring the app forward.
    /// `tty` is the session's tty as a device path ("/dev/ttys003", only a name that passes
    /// `GhosttyTerminals.ttyDevicePath`): with several terminals in the folder, a title
    /// marker written there tells which one runs the session. Without it, none is written.
    case focusTerminalByFolder(TerminalApp, folder: String, tty: String?)
    /// VS Code, VS Code Insiders, Cursor or Windsurf with a window open that holds the
    /// session's folder: open exactly that window's folder (or `.code-workspace` file) with
    /// the editor, which focuses that window.
    case focusWindow(String)
    /// Herdr: ask Desktop to focus this terminal, then bring Desktop forward.
    case focusHerdrTerminal(id: String)
    /// Any other app: bring it forward.
    case activateApp
    /// No app was found in the session's process tree.
    case none

    /// The strategy for a session whose app has `ownerBundleID`, with controlling terminal
    /// `tty` and project `folder`. A folder is used only when it is an existing absolute
    /// directory (checked through `fileSystem`); Ghostty without one is only brought
    /// forward, and gets the tty only when it is a plain pseudo-terminal. An editor's open windows come from its storage.json under `home`
    /// (size-capped); `resolve` resolves symbolic links. The editor is only brought forward,
    /// so that the click opens no new window, when no recorded window holds the folder, the
    /// window state can't be read, the session's process has ended (`sessionAlive`; its
    /// window may have closed since the state was saved) or the editor has no window open
    /// (`openWindowCount`, asked only for these editors; VS Code keeps recording the last
    /// window after it closes).
    /// Herdr uses only a valid `herdrTerminal`; without one Desktop is brought forward.
    public static func plan(
        ownerBundleID: String?, tty: String?, folder: String?, home: String, fileSystem: some FileSystem,
        resolve: (String) -> String = { $0 }, herdrTerminal: String? = nil,
        sessionAlive: Bool, openWindowCount: () -> Int
    ) -> SessionActivation {
        guard let ownerBundleID else { return .none }
        if TerminalApp(bundleID: ownerBundleID) == .herdr {
            guard let id = HerdrTerminal.validID(herdrTerminal) else { return .activateApp }
            return .focusHerdrTerminal(id: id)
        }
        if let app = TerminalApp(bundleID: ownerBundleID), app.selectsTabByTTY, let tty,
            TerminalScripts.selectTab(app, tty: tty) != nil
        {
            return .selectTab(app, tty: tty)
        }
        if TerminalApp(bundleID: ownerBundleID) == .ghostty {
            guard let folder = existingFolder(folder, fileSystem: fileSystem) else { return .activateApp }
            return .focusTerminalByFolder(.ghostty, folder: folder, tty: GhosttyTerminals.ttyDevicePath(tty))
        }
        if let storage = EditorWindows.storagePath(bundleID: ownerBundleID, home: home), sessionAlive,
            openWindowCount() > 0, let folder = existingFolder(folder, fileSystem: fileSystem),
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
