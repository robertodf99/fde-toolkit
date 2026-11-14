import Foundation
import HookMeUpCore

/// The real file system, to check a session's folder and read an editor's window state.
struct LocalFileSystem: FileSystem {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    /// Reads a regular file of at most `limit` bytes without reading more than that. The file
    /// is opened non-blocking (a FIFO never waits for a writer) and checked once open.
    func contents(atPath path: String, limit: Int) -> Data? {
        guard limit >= 0, limit < Int.max else { return nil }
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= off_t(limit) else {
            return nil
        }
        let data: Data?
        do { data = try handle.read(upToCount: limit + 1) } catch { return nil }
        let bytes = data ?? Data()
        return bytes.count <= limit ? bytes : nil
    }

    /// `path` with its symbolic links resolved (and `/private` dropped from /private/var,
    /// /private/tmp and /private/etc), as far as the path exists.
    static func resolvingSymlinks(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
