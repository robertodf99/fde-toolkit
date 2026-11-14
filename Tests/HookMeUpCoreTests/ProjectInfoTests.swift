import Foundation
import Testing

@testable import HookMeUpCore

@Suite struct ProjectInfoTests {
    @Test func projectNameFromGitRoot() throws {
        let tree = try TempTree()
        try tree.file("myproj/.git/HEAD", "ref: refs/heads/main\n")
        let cwd = try tree.dir("myproj/Sources/deep")
        #expect(
            ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "myproj", gitRoot: tree.path("myproj"), branch: "main", worktree: nil,
                    gitCommonDir: tree.path("myproj/.git")))
    }

    @Test func fallbackToCwdBasename() throws {
        let tree = try TempTree()
        let cwd = try tree.dir("plain/folder")
        #expect(
            ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "folder", gitRoot: nil, branch: nil, worktree: nil, folder: tree.path("plain/folder")))
    }

    @Test func worktreeDetected() throws {
        let tree = try TempTree()
        try tree.file("main-repo/.git/HEAD", "ref: refs/heads/main\n")
        try tree.file("main-repo/.git/worktrees/feat/HEAD", "ref: refs/heads/claude/feat\n")
        try tree.file("main-repo/.git/worktrees/feat/commondir", "../..\n")
        try tree.file("feat-wt/.git", "gitdir: \(tree.path("main-repo/.git/worktrees/feat"))\n")
        let cwd = try tree.dir("feat-wt/src")
        // Decision: a linked worktree is shown as the main repository's name plus the worktree folder.
        #expect(
            ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "main-repo", gitRoot: tree.path("feat-wt"), branch: "claude/feat", worktree: "feat-wt",
                    gitCommonDir: tree.path("main-repo/.git")))
    }

    @Test func worktreeWithRelativeGitdir() throws {
        let tree = try TempTree()
        try tree.file("main-repo/.git/worktrees/wt2/HEAD", "ref: refs/heads/topic\n")
        try tree.file("main-repo/.git/worktrees/wt2/commondir", "../..")
        try tree.file("wt2/.git", "gitdir: ../main-repo/.git/worktrees/wt2")
        let cwd = try tree.dir("wt2")
        #expect(
            ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "main-repo", gitRoot: tree.path("wt2"), branch: "topic", worktree: "wt2",
                    gitCommonDir: tree.path("main-repo/.git")))
    }

    @Test func detachedHead() throws {
        let tree = try TempTree()
        try tree.file("repo/.git/HEAD", "0123456789abcdef0123456789abcdef01234567\n")
        let cwd = try tree.dir("repo")
        // Decision: a detached HEAD shows the 7-character short SHA as the branch.
        #expect(ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem()).branch == "0123456")
    }

    @Test func gitFileWithoutCommondirIsNotAWorktree() throws {
        // Submodule layout: `.git` file pointing into the superproject, no commondir.
        let tree = try TempTree()
        try tree.file("super/.git/modules/lib/HEAD", "ref: refs/heads/dev\n")
        try tree.file("super/lib/.git", "gitdir: ../.git/modules/lib\n")
        let cwd = try tree.dir("super/lib")
        #expect(
            ProjectInfo.resolve(cwd: cwd, fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "lib", gitRoot: tree.path("super/lib"), branch: "dev", worktree: nil,
                    gitCommonDir: tree.path("super/.git/modules/lib")))
    }

    @Test func unreadableHeadStillGivesProjectName() throws {
        let tree = try TempTree()
        try tree.dir("repo/.git")
        try tree.file("repo/.git/HEAD", "garbage that is not a ref\n")
        #expect(
            ProjectInfo.resolve(cwd: try tree.dir("repo"), fileSystem: DiskFileSystem())
                == ProjectInfo(
                    name: "repo", gitRoot: tree.path("repo"), branch: nil, worktree: nil,
                    gitCommonDir: tree.path("repo/.git")))
    }

    /// Every working tree of one repository points at the same shared git folder, so
    /// their notifications can be grouped together.
    @Test func aCheckoutAndItsWorktreesShareTheGitCommonDir() throws {
        let tree = try TempTree()
        try tree.file("main-repo/.git/HEAD", "ref: refs/heads/main\n")
        try tree.file("main-repo/.git/worktrees/feat/HEAD", "ref: refs/heads/feat\n")
        try tree.file("main-repo/.git/worktrees/feat/commondir", "../..\n")
        try tree.file("feat-wt/.git", "gitdir: ../main-repo/.git/worktrees/feat\n")
        let main = ProjectInfo.resolve(cwd: try tree.dir("main-repo"), fileSystem: DiskFileSystem())
        let worktree = ProjectInfo.resolve(cwd: try tree.dir("feat-wt"), fileSystem: DiskFileSystem())
        #expect(main.gitRoot != worktree.gitRoot)
        #expect(main.gitCommonDir == worktree.gitCommonDir)
        #expect(main.gitCommonDir == tree.path("main-repo/.git"))
    }
}

/// The real disk, for these tests that build small git layouts in a temporary folder.
private struct DiskFileSystem: FileSystem {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }
}
