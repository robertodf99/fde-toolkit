import Foundation

/// Where things live, derived from the user's home folder. Shared by the hook, the
/// agent and the installer.
public enum HookMeUpPaths {
    /// The agent's private support folder (`0700`) for the user whose home folder is `home`:
    /// its socket, the installer's state and the editor extension's request.
    public static func supportFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/hook-me-up", isDirectory: true)
    }

    /// The agent's socket for the user whose home folder is `home`.
    public static func socketURL(home: URL) -> URL {
        supportFolder(home: home).appendingPathComponent("agent.sock")
    }

    /// Where the agent asks the editor extension to show a session's terminal (see
    /// `EditorExtension`).
    public static func editorFocusRequestURL(home: URL) -> URL {
        supportFolder(home: home).appendingPathComponent(EditorExtension.requestFileName)
    }

    /// The socket in the current user's home directory, taken from the user database
    /// (not `$HOME`), so the hook and the agent agree whatever their environment.
    public static var defaultSocketURL: URL { socketURL(home: homeDirectory) }

    /// Claude Code's user settings file (`~/.claude/settings.json`).
    public static var claudeSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    /// Codex user hooks. CODEX_HOME may select an isolated Codex profile.
    public static func codexHooksURL(
        home: URL = homeDirectory, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let folder =
            environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        return folder.appendingPathComponent("hooks.json")
    }

    /// Where `make install` puts the hook (inside the installed app).
    public static var installedHookPath: String {
        homeDirectory.appendingPathComponent("Applications/Hook Me Up.app/Contents/MacOS/hook-me-up").path
    }

    /// The current user's home folder from the user database (`getpwuid_r`), falling
    /// back to `$HOME`.
    public static var homeDirectory: URL {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        if getpwuid_r(getuid(), &record, &buffer, buffer.count, &result) == 0, result != nil, let dir = record.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
