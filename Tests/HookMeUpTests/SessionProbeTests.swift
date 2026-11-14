import CoreGraphics
import Foundation
import Testing

@testable import HookMeUp

/// Whether a session's process still runs, and how many normal windows an app has.
@Suite struct SessionProbeTests {
    @Test func aRunningProcessIsAlive() {
        #expect(SessionProbe.isAlive(getpid()))
        #expect(SessionProbe.isAlive(getppid()))
    }

    @Test func aFinishedOrUnknownProcessIsNot() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        #expect(!SessionProbe.isAlive(child.processIdentifier))
        #expect(!SessionProbe.isAlive(999_999))
        #expect(!SessionProbe.isAlive(nil))
        #expect(!SessionProbe.isAlive(0))
        #expect(!SessionProbe.isAlive(-1))
    }

    /// A process that has exited but was not reaped yet (a zombie) is not alive.
    @Test func aZombieIsNotAlive() throws {
        var pid: pid_t = 0
        let path = "/usr/bin/true"
        let arguments: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { for argument in arguments { free(argument) } }
        #expect(posix_spawn(&pid, path, nil, nil, arguments, nil) == 0)
        defer { waitpid(pid, nil, 0) }
        var waited = 0
        while kill(pid, 0) == 0, SessionProbe.isAlive(pid), waited < 200 {  // until it exits, at most 2 s
            usleep(10_000)
            waited += 1
        }
        #expect(kill(pid, 0) == 0)  // still there: a zombie
        #expect(!SessionProbe.isAlive(pid))
    }

    /// A normal window is on layer 0, visible and at least 100 × 100 points; apps also own
    /// invisible or tiny layer-0 windows (seen for VS Code and Finder).
    @Test func onlyNormalWindowsCount() {
        func info(layer: Int = 0, alpha: Double = 1, width: Double = 1512, height: Double = 949) -> [String: Any] {
            [
                kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": width, "Height": height],
            ]
        }
        #expect(SessionProbe.isNormalWindow(info()))
        #expect(SessionProbe.isNormalWindow(info(width: 400, height: 270)))
        #expect(!SessionProbe.isNormalWindow(info(layer: 25)))
        #expect(!SessionProbe.isNormalWindow(info(alpha: 0)))
        #expect(!SessionProbe.isNormalWindow(info(height: 33)))
        #expect(!SessionProbe.isNormalWindow(info(width: 64, height: 64)))
        #expect(!SessionProbe.isNormalWindow([kCGWindowLayer as String: 0]))
    }

    /// The test process has no windows; neither has a process that doesn't exist.
    @Test func windowlessProcessesHaveNoWindows() {
        #expect(SessionProbe.normalWindowCount(of: getpid()) == 0)
        #expect(SessionProbe.normalWindowCount(of: 999_999) == 0)
    }
}
