import Foundation

let usage = """
    usage: hook-me-up-setup install|uninstall [--settings <path>] [--hook <path>] [--state <path>] \
    [--timeout <seconds>] [--dry-run] [--yes]
           hook-me-up-setup doctor [--settings <path>] [--app <path>] [--socket <path>] [--home <path>]
           hook-me-up-setup notifications [--wait <seconds>] [--test] [--open-settings | --open-settings-if-off] \
    [--socket <path>] [--result-file <path>]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("hook-me-up-setup: \(message)\n".utf8))
    exit(1)
}

/// An absolute path for a command-line value (`~` expanded, relative to the current folder).
func absolutePath(_ value: String) -> String {
    URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL.path
}
