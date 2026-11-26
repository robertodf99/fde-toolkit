import Foundation

/// Which project a request comes from.
public struct ProjectInfo: Codable, Equatable, Sendable {
    /// Repository name (main repository for a linked worktree), else the cwd's basename.
    public var name: String
    /// Top of the working tree containing cwd (the worktree root for a linked worktree).
    public var gitRoot: String?
    /// Branch name, or the 7-character short SHA when HEAD is detached.
    public var branch: String?
    /// Folder name of a linked worktree; nil for a normal checkout.
    public var worktree: String?
    /// The repository's shared git folder: the checkout's `.git`, the main `.git` for a
    /// linked worktree (its `commondir`), or a submodule's git folder. Every working tree
    /// of one repository has the same value.
    public var gitCommonDir: String?
    /// The working folder when it is not inside a git repository (nil otherwise), so two
    /// folders with the same name can be told apart.
    public var folder: String?

    /// Creates project information.
    public init(
        name: String, gitRoot: String?, branch: String?, worktree: String?, gitCommonDir: String? = nil,
        folder: String? = nil
    ) {
        self.name = name
        self.gitRoot = gitRoot
        self.branch = branch
        self.worktree = worktree
        self.gitCommonDir = gitCommonDir
        self.folder = folder
    }

    private static let maxSmallFileBytes = 4096
    private static let maxDepth = 128

    /// The project that `cwd` belongs to, read through `fileSystem` (`.git` folder or
    /// file, `HEAD`, `commondir`); no git subprocess.
    public static func resolve(cwd: URL, fileSystem fs: some FileSystem) -> ProjectInfo {
        let start = cwd.standardizedFileURL
        var directory = start
        for _ in 0..<maxDepth {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fs.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if let info = fromDotGit(dotGit, isDirectory: isDirectory.boolValue, root: directory, fs: fs) {
                    return info
                }
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path { break }
            directory = parent
        }
        let base = start.lastPathComponent
        return ProjectInfo(
            name: base.isEmpty ? start.path : base, gitRoot: nil, branch: nil, worktree: nil, folder: start.path)
    }

    private static func fromDotGit(_ dotGit: URL, isDirectory: Bool, root: URL, fs: some FileSystem) -> ProjectInfo? {
        let rootName = root.lastPathComponent
        guard !isDirectory else {
            return ProjectInfo(
                name: rootName, gitRoot: root.path, branch: branch(gitDir: dotGit, fs: fs), worktree: nil,
                gitCommonDir: dotGit.standardizedFileURL.path)
        }
        // `.git` file: "gitdir: <path>" (linked worktree or submodule).
        guard let text = readSmall(dotGit, fs: fs),
            let line = text.split(whereSeparator: \.isNewline).first,
            line.hasPrefix("gitdir:")
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        // Relative paths resolve against the folder holding `.git` (base = the file itself).
        let gitDir = URL(fileURLWithPath: target, relativeTo: dotGit).standardizedFileURL
        let branch = branch(gitDir: gitDir, fs: fs)

        // Only linked worktrees have a `commondir` file; it points at the main .git.
        if let common = readSmall(gitDir.appendingPathComponent("commondir"), fs: fs)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty
        {
            let commonDir = URL(fileURLWithPath: common, relativeTo: gitDir.appendingPathComponent("x"))
                .standardizedFileURL
            let mainName: String
            if commonDir.lastPathComponent == ".git" {
                mainName = commonDir.deletingLastPathComponent().lastPathComponent
            } else {
                // Bare main repository, e.g. "repo.git".
                let bare = commonDir.lastPathComponent
                mainName = bare.hasSuffix(".git") ? String(bare.dropLast(4)) : bare
            }
            return ProjectInfo(
                name: mainName.isEmpty ? rootName : mainName, gitRoot: root.path,
                branch: branch, worktree: rootName, gitCommonDir: commonDir.path)
        }
        return ProjectInfo(
            name: rootName, gitRoot: root.path, branch: branch, worktree: nil, gitCommonDir: gitDir.path)
    }

    private static func branch(gitDir: URL, fs: some FileSystem) -> String? {
        guard
            let head = readSmall(gitDir.appendingPathComponent("HEAD"), fs: fs)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if head.hasPrefix("ref:") {
            let ref = head.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
            return ref.isEmpty ? nil : ref
        }
        let isSHA = (head.count == 40 || head.count == 64) && head.allSatisfy(\.isHexDigit)
        return isSHA ? String(head.prefix(7)) : nil
    }

    private static func readSmall(_ url: URL, fs: some FileSystem) -> String? {
        guard let data = fs.contents(atPath: url.path), data.count <= maxSmallFileBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
