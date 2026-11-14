import Darwin
import Foundation
import HookMeUpCore

/// Finds the app that owns a session from the hook's ancestor PIDs.
enum TerminalLookup {
    /// The terminal app (pid and bundle id) among the hook's ancestors, if any.
    static func owner(hint: TerminalHint) -> TerminalMapping.Owner? {
        let ancestors = hint.ancestorPIDs.compactMap { pid -> (pid: pid_t, path: String)? in
            executablePath(pid).map { (pid, $0) }
        }
        return TerminalMapping.owner(ancestors: ancestors) { Bundle(path: $0)?.bundleIdentifier }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
