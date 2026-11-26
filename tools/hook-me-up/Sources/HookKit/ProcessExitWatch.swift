import Darwin
import Foundation
import HookMeUpIPC

/// Runs `onExit` once when process `pid` exits (at once if it is already gone).
final class ProcessExitWatch: @unchecked Sendable {
    private let source: DispatchSourceProcess

    init(pid: pid_t, onExit: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler(handler: onExit)
        source.resume()
        // Registered too late for a process that had already exited.
        if kill(pid, 0) == -1, errno == ESRCH { onExit() }
    }

    func cancel() {
        source.cancel()
    }
}
