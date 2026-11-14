import Foundation

/// Where a copy of Hook Me Up lives, from the path of one of its executables: the app
/// bundle, Homebrew's stable path for it, and the hook next to `hook-me-up-setup`.
public enum AppLocation {
    /// The app bundle that has `executable` in its `Contents/MacOS`, if any.
    public static func appContaining(_ executable: String) -> String? {
        let macOS = (executable as NSString).deletingLastPathComponent
        let contents = (macOS as NSString).deletingLastPathComponent
        let app = (contents as NSString).deletingLastPathComponent
        guard (macOS as NSString).lastPathComponent == "MacOS", (contents as NSString).lastPathComponent == "Contents",
            app.hasSuffix(".app")
        else { return nil }
        return app
    }

    /// For a path inside a Homebrew keg (`<prefix>/Cellar/hook-me-up/<version>/…`), the
    /// same path under `<prefix>/opt/hook-me-up/…`, which stays the same across upgrades;
    /// nil for any other path.
    public static func homebrewOptPath(for canonicalPath: String) -> String? {
        guard let keg = canonicalPath.range(of: "/Cellar/hook-me-up/") else { return nil }
        let inKeg = canonicalPath[keg.upperBound...].drop { $0 != "/" }
        guard !canonicalPath[..<keg.lowerBound].isEmpty, !inKeg.isEmpty else { return nil }
        return String(canonicalPath[..<keg.lowerBound]) + "/opt/hook-me-up" + inKeg
    }

    /// The hook `install` and `uninstall` use without `--hook`: the one next to the
    /// running `hook-me-up-setup` (`setupExecutable`, symlinks resolved), at Homebrew's
    /// opt path for a keg; `fallback` when this setup isn't inside an app with a hook.
    public static func defaultHookPath(
        setupExecutable: String?, canonicalPath: (String) -> String, isExecutable: (String) -> Bool,
        fallback: String
    ) -> String {
        guard let executable = setupExecutable, let app = appContaining(canonicalPath(executable)) else {
            return fallback
        }
        let hook = app + "/Contents/MacOS/hook-me-up"
        guard isExecutable(hook) else { return fallback }
        if let opt = homebrewOptPath(for: hook), isExecutable(opt), canonicalPath(opt) == hook { return opt }
        return hook
    }

    /// `path` with its symlinks resolved, as far as it exists.
    public static func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
