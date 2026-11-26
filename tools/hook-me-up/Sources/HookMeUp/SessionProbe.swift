import CoreGraphics
import Darwin
import Foundation

/// What a click needs to know before opening anything in an editor or writing to a
/// terminal, read without any permission: whether the session's process still runs, its
/// controlling terminal, and how many normal windows the editor has. The window list gives
/// owner, layer, alpha and bounds without Screen Recording permission; only titles are
/// withheld, and they are not used.
enum SessionProbe {
    /// Whether `pid` is a running process: it can be signalled and still has an executable
    /// (a zombie has none).
    static func isAlive(_ pid: pid_t?) -> Bool {
        guard let pid, pid > 0 else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0
    }

    /// The device number of `pid`'s controlling terminal, when it has one (read with sysctl,
    /// as the hook reads the tty's name; the app doesn't depend on the hook's library).
    static func controllingTTYDevice(of pid: pid_t) -> dev_t? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &process, &size, nil, 0) == 0, size > 0, process.kp_proc.p_pid == pid
        else { return nil }
        let device = process.kp_eproc.e_tdev
        return device == -1 ? nil : device  // NODEV: no controlling terminal
    }

    /// The normal windows of the app whose process is `pid`, on screen or not.
    static func normalWindowCount(of pid: pid_t) -> Int {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && isNormalWindow($0) }.count
    }

    /// A window on the normal layer, not transparent and at least 100 × 100 points. Apps
    /// also own invisible or tiny layer-0 windows (VS Code and Finder have several), which
    /// are not windows a user can bring forward.
    static func isNormalWindow(_ info: [String: Any]) -> Bool {
        guard (info[kCGWindowLayer as String] as? Int) == 0, (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return false }
        return rect.width >= 100 && rect.height >= 100
    }
}
