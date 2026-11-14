import Foundation

/// Where things live, derived from the user's home folder. Shared by the hook, the
/// agent and the installer.
public enum HookMeUpPaths {
    /// The agent's socket for the user whose home folder is `home`.
    static func socketURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/hook-me-up/agent.sock")
    }

    /// The socket in the current user's home directory, taken from the user database
    /// (not `$HOME`), so the hook and the agent agree whatever their environment.
    public static var defaultSocketURL: URL { socketURL(home: homeDirectory) }

    /// Claude Code's user settings file (`~/.claude/settings.json`).
    public static var claudeSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
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
