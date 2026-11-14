import Foundation

/// Resolves paths the way the shell in `cwd` would and compares them to the project root.
struct PathContext {
    let root: String
    let cwd: String
    let home: String

    init(root: String, cwd: String, home: String) {
        self.home = Self.normalize(home)
        self.cwd = Self.normalize(cwd)
        self.root = Self.normalize(root)
    }

    func absolute(_ path: String) -> String {
        var expanded = path
        for prefix in ["~/", "$HOME/", "${HOME}/"] where path.hasPrefix(prefix) {
            expanded = home + "/" + path.dropFirst(prefix.count)
        }
        if ["~", "$HOME", "${HOME}"].contains(path) { expanded = home }
        if !expanded.hasPrefix("/") { expanded = cwd + "/" + expanded }
        return Self.normalize(expanded)
    }

    func isInside(_ path: String) -> Bool {
        let absolutePath = absolute(path)
        return absolutePath == root || absolutePath.hasPrefix(root == "/" ? "/" : root + "/")
    }

    /// Path relative to the project root when inside it, else with `~` for home.
    func display(_ path: String) -> String {
        let absolutePath = absolute(path)
        if absolutePath == root { return "." }
        if absolutePath.hasPrefix(root + "/") { return String(absolutePath.dropFirst(root.count + 1)) }
        if absolutePath.hasPrefix(home + "/") { return "~/" + absolutePath.dropFirst(home.count + 1) }
        return absolutePath
    }

    /// Lexical normalization ("." and ".." removed); /private/{tmp,var,etc} folded into
    /// /tmp, /var, /etc so both spellings of the same place compare equal.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(component)
        }
        var result = "/" + parts.joined(separator: "/")
        for alias in ["/private/tmp", "/private/var", "/private/etc"]
        where result == alias || result.hasPrefix(alias + "/") {
            result = String(result.dropFirst("/private".count))
        }
        return result
    }
}
