import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUp

/// A throwaway folder, removed when the value goes away.
private final class Scratch {
    let root: String

    init() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url.path
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func path(_ relative: String) -> String { root + "/" + relative }
}

/// The app's file access: size-capped reads that never block, and symlink resolution.
@Suite struct LocalFileSystemTests {
    @Test func aSmallFileIsRead() throws {
        let scratch = try Scratch()
        try Data("12345".utf8).write(to: URL(fileURLWithPath: scratch.path("five")))
        #expect(LocalFileSystem().contents(atPath: scratch.path("five"), limit: 5) == Data("12345".utf8))
        #expect(LocalFileSystem().contents(atPath: scratch.path("five"), limit: 4) == nil)
    }

    @Test func folderFifoAndMissingFileAreNotRead() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(atPath: scratch.path("folder"), withIntermediateDirectories: false)
        #expect(mkfifo(scratch.path("fifo"), 0o600) == 0)
        let files = LocalFileSystem()
        #expect(files.contents(atPath: scratch.path("folder"), limit: 1 << 20) == nil)
        #expect(files.contents(atPath: scratch.path("fifo"), limit: 1 << 20) == nil)  // returns at once
        #expect(files.contents(atPath: scratch.path("missing"), limit: 1 << 20) == nil)
    }

    /// A session folder reached through a symbolic link (and the temporary folder's
    /// `/private` alias) finds the window open on the real folder.
    @Test func symbolicLinksAreResolvedWhenMatchingWindows() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.path("acme/.worktrees/login"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: scratch.path("link"), withDestinationPath: scratch.path("acme"))
        let real = URL(fileURLWithPath: scratch.path("acme")).resolvingSymlinksInPath().path
        let window = EditorWindow(target: "/private" + real, roots: ["/private" + real])
        let found = EditorWindows.best(
            for: scratch.path("link/.worktrees/login"), among: [window], resolve: LocalFileSystem.resolvingSymlinks)
        #expect(found == window)
        #expect(EditorWindows.best(for: scratch.path("link/.worktrees/login"), among: [window]) == nil)
    }
}
