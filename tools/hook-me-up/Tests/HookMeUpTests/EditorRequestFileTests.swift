import Darwin
import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUp

/// A private folder like the agent's support folder (`0700`), removed afterwards.
private final class SupportFolder {
    let url: URL
    var request: URL { url.appendingPathComponent(EditorExtension.requestFileName) }

    init(mode: mode_t = 0o700) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-request-\(UUID().uuidString)")
        try #require(mkdir(url.path, 0o700) == 0)
        try #require(chmod(url.path, mode) == 0)
    }

    var entries: [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] }

    deinit {
        chmod(url.path, 0o700)
        try? FileManager.default.removeItem(at: url)
    }
}

private func info(_ path: String) -> stat? {
    var result = stat()
    return lstat(path, &result) == 0 ? result : nil
}

private let request = Data(
    #"{"created":1731672000123,"nonce":"0123456789abcdef0123456789abcdef","pids":[4242],"version":1}"#.utf8)

/// The editor extension's request is written atomically, `0600`, only into the agent's
/// own private folder.
@Suite struct EditorRequestFileTests {
    @Test func theRequestIsWrittenPrivately() throws {
        let folder = try SupportFolder()
        #expect(EditorRequestFile.write(request, to: folder.request))
        #expect(try Data(contentsOf: folder.request) == request)
        let file = try #require(info(folder.request.path))
        #expect(file.st_mode & S_IFMT == S_IFREG)
        #expect(file.st_mode & 0o777 == 0o600)
        #expect(file.st_uid == getuid())
        #expect(folder.entries == [EditorExtension.requestFileName])  // no temporary file left
    }

    /// A new file is renamed over the earlier one (another inode), so the extension never
    /// reads half a request.
    @Test func aNewRequestReplacesTheEarlierOneAtomically() throws {
        let folder = try SupportFolder()
        #expect(EditorRequestFile.write(Data("first".utf8), to: folder.request))
        let first = try #require(info(folder.request.path))
        #expect(EditorRequestFile.write(request, to: folder.request))
        let second = try #require(info(folder.request.path))
        #expect(try Data(contentsOf: folder.request) == request)
        #expect(first.st_ino != second.st_ino)
        #expect(folder.entries == [EditorExtension.requestFileName])
    }

    /// A symlink at the request's name is replaced, never followed.
    @Test func aSymlinkAtTheRequestIsReplaced() throws {
        let folder = try SupportFolder()
        let target = folder.url.appendingPathComponent("elsewhere")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: folder.request.path, withDestinationPath: target.path)
        #expect(EditorRequestFile.write(request, to: folder.request))
        #expect(info(folder.request.path).map { $0.st_mode & S_IFMT } == S_IFREG)
        #expect(try Data(contentsOf: target) == Data("keep".utf8))
    }

    @Test func aMissingFolderIsNotCreated() throws {
        let folder = try SupportFolder()
        let missing = folder.url.appendingPathComponent("gone").appendingPathComponent(EditorExtension.requestFileName)
        #expect(!EditorRequestFile.write(request, to: missing))
        #expect(folder.entries.isEmpty)
    }

    /// Only a folder no one else can read or enter (the agent keeps it `0700`).
    @Test(arguments: [0o755 as mode_t, 0o750, 0o701, 0o770])
    func aFolderOthersCanReachIsRefused(_ mode: mode_t) throws {
        let folder = try SupportFolder(mode: mode)
        #expect(!EditorRequestFile.write(request, to: folder.request))
        #expect(folder.entries.isEmpty)
    }

    @Test func aSymlinkedFolderIsRefused() throws {
        let folder = try SupportFolder()
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hmu-request-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: folder.url.path)
        defer { try? FileManager.default.removeItem(at: link) }
        #expect(!EditorRequestFile.write(request, to: link.appendingPathComponent(EditorExtension.requestFileName)))
        #expect(folder.entries.isEmpty)
    }

    @Test func aFileInsteadOfTheFolderIsRefused() throws {
        let folder = try SupportFolder()
        let file = folder.url.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        #expect(!EditorRequestFile.write(request, to: file.appendingPathComponent(EditorExtension.requestFileName)))
        #expect(folder.entries == ["not-a-folder"])
    }
}
