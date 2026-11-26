import Darwin
import Foundation

/// Writes the editor extension's request (see `EditorExtension`), only into the agent's
/// own private folder and atomically: the folder, opened without following a symbolic
/// link, must be a folder of this user that no one else can read or enter (the agent keeps
/// it `0700`; nothing is created or changed here); the request goes into a new `0600` file
/// in it, renamed over the request's name (a file or link there is replaced, never
/// followed), so the extension reads a whole request or none.
enum EditorRequestFile {
    static func write(_ data: Data, to url: URL) -> Bool {
        let name = url.lastPathComponent
        let folder = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { return false }
        defer { close(folder) }
        var info = stat()
        guard fstat(folder, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
            info.st_mode & 0o077 == 0
        else { return false }

        var generator = SystemRandomNumberGenerator()
        let temporary = ".\(name).\(String(generator.next(), radix: 16)).tmp"
        let file = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { return false }
        var written = fchmod(file, 0o600) == 0 && writeAll(data, to: file)
        written = close(file) == 0 && written
        guard written, renameat(folder, temporary, folder, name) == 0 else {
            unlinkat(folder, temporary, 0)
            return false
        }
        return true
    }

    private static func writeAll(_ data: Data, to file: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return buffer.isEmpty }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, base + offset, buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }
}
