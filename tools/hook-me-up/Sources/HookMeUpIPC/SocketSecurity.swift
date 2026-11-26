import Darwin
import Foundation

/// The socket's file-system and peer checks.
enum SocketSecurity {
    /// Creates `url` as a 0700 directory owned by us, or verifies an existing one:
    /// symlinks, non-directories and directories owned by someone else are refused; a
    /// directory we own with another mode is chmod-ed to 0700. Checks and the chmod go
    /// through one descriptor opened with O_NOFOLLOW, so nothing can be swapped between.
    static func prepareDirectory(_ url: URL) throws {
        let path = url.path
        var info = stat()
        if lstat(path, &info) != 0 {
            let code = errno
            guard code == ENOENT else { throw SocketError.system(call: "lstat", code: code) }
            let parent = url.deletingLastPathComponent().path
            if !FileManager.default.fileExists(atPath: parent) {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            if mkdir(path, 0o700) != 0, errno != EEXIST { throw SocketError.system(call: "mkdir", code: errno) }
        }

        var fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            let code = errno
            guard lstat(path, &info) == 0 else { throw SocketError.system(call: "open", code: code) }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK { throw SocketError.symlinkRefused(path) }
            if type != S_IFDIR { throw SocketError.notADirectory(path) }
            // Our own directory without read permission (e.g. 0300): restore it, retry once.
            guard code == EACCES, info.st_uid == getuid(), chmod(path, 0o700) == 0 else {
                throw SocketError.system(call: "open", code: code)
            }
            fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw SocketError.system(call: "open", code: errno) }
        }
        defer { close(fd) }

        guard fstat(fd, &info) == 0 else { throw SocketError.system(call: "fstat", code: errno) }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw SocketError.notADirectory(path) }
        guard info.st_uid == getuid() else { throw SocketError.wrongOwner(path) }
        if info.st_mode & 0o777 != 0o700 {
            guard fchmod(fd, 0o700) == 0 else { throw SocketError.system(call: "fchmod", code: errno) }
        }
    }

    /// UID of the process at the other end of a connected Unix socket.
    static func peerUID(fd: Int32) throws -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw SocketError.system(call: "getpeereid", code: errno) }
        return uid
    }
}
