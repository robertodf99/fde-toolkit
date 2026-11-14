import Darwin
import Foundation

/// The hook's process ancestry, used to find the terminal app that owns a session.
public enum ProcessTree {
    /// Parent, grandparent, ... of `pid` (nearest first), excluding `pid` itself and
    /// launchd (pid 1). Empty for an unknown pid.
    static func ancestors(of pid: pid_t) -> [(pid: pid_t, path: String)] {
        var result: [(pid: pid_t, path: String)] = []
        var seen: Set<pid_t> = [pid]
        var current = info(pid)?.kp_eproc.e_ppid
        while let next = current, next > 1, !seen.contains(next), result.count < 64 {
            seen.insert(next)
            result.append((next, executablePath(next) ?? ""))
            current = info(next)?.kp_eproc.e_ppid
        }
        return result
    }

    /// The process that runs the hook for the session: the nearest ancestor that is not
    /// a shell (Claude Code may run hooks directly or through `sh -c`).
    public static func sessionProcess(of pid: pid_t) -> pid_t? {
        sessionAncestors(of: pid).first?.pid
    }

    /// The ancestors from the session's process up: without the shells that only ran the
    /// hook, which exit with it.
    static func sessionAncestors(of pid: pid_t) -> [(pid: pid_t, path: String)] {
        droppingLeadingShells(ancestors(of: pid))
    }

    /// `ancestors` without the shells at its start.
    static func droppingLeadingShells(_ ancestors: [(pid: pid_t, path: String)]) -> [(pid: pid_t, path: String)] {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "tcsh", "csh"]
        return Array(ancestors.drop { shells.contains(($0.path as NSString).lastPathComponent) })
    }

    /// Controlling terminal name of a process ("ttys003"), if it has one.
    static func controllingTTY(of pid: pid_t) -> String? {
        guard let device = info(pid)?.kp_eproc.e_tdev, device != -1, let name = devname(device, S_IFCHR) else {
            return nil
        }
        let text = String(cString: name)
        return text.isEmpty || text == "??" ? nil : text
    }

    static func info(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &process, &size, nil, 0) == 0, size > 0 else { return nil }
        return process
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
