import Foundation

/// Finds the app that runs a session from the hook's ancestor processes.
public enum TerminalMapping {
    /// The app that owns a session, and the process to activate (its main process).
    public struct Owner: Equatable, Sendable {
        /// The app's bundle identifier.
        public let bundleID: String
        /// The app bundle's path.
        public let appPath: String
        /// The app's main process.
        public let pid: pid_t

        /// Creates an owner.
        public init(bundleID: String, appPath: String, pid: pid_t) {
            self.bundleID = bundleID
            self.appPath = appPath
            self.pid = pid
        }
    }

    /// The outermost ".app" bundle containing `path`: a helper inside
    /// "Visual Studio Code.app/Contents/Frameworks/Code Helper.app" belongs to VS Code.
    static func outermostAppBundle(ofExecutable path: String) -> String? {
        var prefix = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            prefix += "/" + component
            if component.hasSuffix(".app") { return prefix }
        }
        return nil
    }

    /// Walks the hook's ancestors (nearest first): the nearest known terminal app wins,
    /// else the nearest app bundle of any kind; nil when no ancestor lives in an app
    /// (e.g. tmux, ssh). `bundleID` reads an app bundle's identifier.
    public static func owner(ancestors: [(pid: pid_t, path: String)], bundleID: (String) -> String?) -> Owner? {
        var apps: [(index: Int, appPath: String, bundleID: String)] = []
        for (index, ancestor) in ancestors.enumerated() {
            guard let appPath = outermostAppBundle(ofExecutable: ancestor.path), let id = bundleID(appPath) else {
                continue
            }
            apps.append((index, appPath, id))
        }
        guard let chosen = apps.first(where: { TerminalApp(bundleID: $0.bundleID) != nil }) ?? apps.first else {
            return nil
        }
        // The farthest ancestor inside the same app is its main process (not a helper).
        let main = apps.last { $0.appPath == chosen.appPath } ?? chosen
        return Owner(bundleID: chosen.bundleID, appPath: chosen.appPath, pid: ancestors[main.index].pid)
    }
}
