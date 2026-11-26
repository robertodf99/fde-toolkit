import Darwin

/// Writes a few bytes (a terminal title sequence) to a session's terminal, only when the
/// path really is that terminal: a character device owned by this user whose device
/// number is the session's controlling tty (`expectedDevice`, from the session's live
/// process). The path is checked without following symbolic links before it is opened
/// (nothing else is ever opened), opened write-only, without becoming this process's
/// controlling terminal, non-blocking and without following a link, and checked again
/// once open. One write: when it is cut short, a BEL ends the title sequence it started,
/// so the terminal doesn't take what follows for part of the title.
enum TTYWriter {
    static func write(_ bytes: [UInt8], toDevice path: String, expectedDevice: dev_t) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, isSessionTerminal(info, expectedDevice: expectedDevice) else { return false }
        let descriptor = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0, isSessionTerminal(info, expectedDevice: expectedDevice) else {
            return false
        }
        return writeOnce(bytes) { buffer in Darwin.write(descriptor, buffer.baseAddress, buffer.count) }
    }

    /// A character device of this user with the session's device number.
    static func isSessionTerminal(_ info: stat, expectedDevice: dev_t) -> Bool {
        info.st_mode & S_IFMT == S_IFCHR && info.st_uid == getuid() && info.st_rdev == expectedDevice
    }

    /// Writes `bytes` with one call to `write`; true when all of them went. After a short
    /// write, a BEL (which ends a title sequence) is written too.
    static func writeOnce(_ bytes: [UInt8], using write: (UnsafeRawBufferPointer) -> Int) -> Bool {
        let written = bytes.withUnsafeBytes { write($0) }
        if written == bytes.count { return true }
        if written > 0 { _ = [UInt8(0x07)].withUnsafeBytes { write($0) } }
        return false
    }
}
