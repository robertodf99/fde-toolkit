import Darwin
import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUp

/// A pseudo-terminal pair: what is written to the terminal (`path`) is read from `master`.
private final class PseudoTerminal {
    let master: Int32
    let terminal: Int32
    let path: String
    let device: dev_t

    init() throws {
        var master: Int32 = -1
        var terminal: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        try #require(openpty(&master, &terminal, &name, nil, nil) == 0)
        // Raw output: the bytes arrive exactly as written.
        var settings = termios()
        tcgetattr(terminal, &settings)
        cfmakeraw(&settings)
        tcsetattr(terminal, TCSANOW, &settings)
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)
        var info = stat()
        try #require(fstat(terminal, &info) == 0)
        self.master = master
        self.terminal = terminal
        self.path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        self.device = info.st_rdev
    }

    /// What reached the terminal, waiting up to `timeout` seconds for the first bytes.
    func received(timeout: TimeInterval = 1) -> [UInt8] {
        var bytes: [UInt8] = []
        var poller = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var wait = Int32(timeout * 1000)
        while poll(&poller, 1, wait) > 0 {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(master, &buffer, buffer.count)
            guard count > 0 else { break }
            bytes += buffer.prefix(count)
            wait = 50  // the rest, if any, follows at once
        }
        return bytes
    }

    deinit {
        close(master)
        close(terminal)
    }
}

private let marker = GhosttyTerminals.titleSequence("hmu-0123456789abcdef")

/// TTYWriter writes to a session's terminal only when the path is that terminal: a
/// character device of this user whose device number is the session's controlling tty.
@Suite struct TTYWriterTests {
    @Test func theBytesReachTheTerminal() throws {
        let pty = try PseudoTerminal()
        #expect(TTYWriter.write(marker, toDevice: pty.path, expectedDevice: pty.device))
        #expect(pty.received() == marker)
    }

    /// A character device, but root's (and not the session's).
    @Test func devNullIsRefused() {
        var info = stat()
        #expect(stat("/dev/null", &info) == 0)
        #expect(!TTYWriter.write(marker, toDevice: "/dev/null", expectedDevice: info.st_rdev))
    }

    @Test func aRegularFileIsRefused() throws {
        let pty = try PseudoTerminal()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-tty-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(!TTYWriter.write(marker, toDevice: file.path, expectedDevice: pty.device))
        #expect(try Data(contentsOf: file).isEmpty)
    }

    /// Even one that points at the session's own terminal.
    @Test func aSymlinkIsRefused() throws {
        let pty = try PseudoTerminal()
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("hmu-tty-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: pty.path)
        defer { try? FileManager.default.removeItem(at: link) }
        #expect(!TTYWriter.write(marker, toDevice: link.path, expectedDevice: pty.device))
        #expect(pty.received(timeout: 0.2).isEmpty)
    }

    /// Another terminal than the session's (a tty name reused after the session ended).
    @Test func anotherTerminalIsRefused() throws {
        let session = try PseudoTerminal()
        let other = try PseudoTerminal()
        #expect(!TTYWriter.write(marker, toDevice: other.path, expectedDevice: session.device))
        #expect(other.received(timeout: 0.2).isEmpty)
        #expect(session.received(timeout: 0.2).isEmpty)
    }

    @Test func aMissingDeviceIsRefused() {
        #expect(!TTYWriter.write(marker, toDevice: "/dev/ttys9999", expectedDevice: 0))
    }

    /// One write; when it is cut short, a BEL ends the title sequence it started.
    @Test func aShortWriteIsEndedWithABell() {
        var calls: [[UInt8]] = []
        let short = TTYWriter.writeOnce(marker) { buffer in
            calls.append(Array(buffer))
            return calls.count == 1 ? 5 : buffer.count
        }
        #expect(!short)
        #expect(calls == [marker, [0x07]])
    }

    @Test func aFailedWriteWritesNothingMore() {
        var calls = 0
        #expect(
            !TTYWriter.writeOnce(marker) { _ in
                calls += 1
                return -1
            })
        #expect(calls == 1)
    }

    @Test func aFullWriteIsOneCall() {
        var calls = 0
        #expect(
            TTYWriter.writeOnce(marker) { buffer in
                calls += 1
                return buffer.count
            })
        #expect(calls == 1)
    }
}

/// The controlling terminal of a session's process, as a device number.
@Suite struct ControllingTTYTests {
    /// `script` runs a shell with a new pseudo-terminal as its controlling terminal; the
    /// shell prints its pid and its tty.
    @Test func aProcessInATerminalHasThatTerminalsDevice() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/sh", "-c", #"echo " pid $$ $(tty) end"; exec sleep 10"#]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate() }
        let line = try #require(firstLine(containing: " end", from: output.fileHandleForReading, timeout: 5))
        let words = line.split(separator: " ")
        let index = try #require(words.firstIndex(of: "pid"))
        try #require(words.count > index + 2)
        let pid = try #require(pid_t(words[index + 1]))
        defer { kill(pid, SIGTERM) }
        let path = String(words[index + 2])
        #expect(GhosttyTerminals.ttyDevicePath(path) == path)
        var info = stat()
        try #require(stat(path, &info) == 0)
        #expect(SessionProbe.controllingTTYDevice(of: pid) == info.st_rdev)
    }

    @Test func noProcessNoTerminal() {
        #expect(SessionProbe.controllingTTYDevice(of: 999_999) == nil)
        #expect(SessionProbe.controllingTTYDevice(of: 0) == nil)
        #expect(SessionProbe.controllingTTYDevice(of: -1) == nil)
    }

    /// Reads `handle` on another thread until a line contains `marker`.
    private func firstLine(containing marker: String, from handle: FileHandle, timeout: TimeInterval) -> String? {
        let found = LineBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var text = ""
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                text += String(decoding: data, as: UTF8.self)
                if let line = text.split(whereSeparator: \.isNewline).first(where: { $0.contains(marker) }) {
                    found.line = String(line)
                    break
                }
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
        return found.line
    }
}

private final class LineBox: @unchecked Sendable {
    var line: String?
}
