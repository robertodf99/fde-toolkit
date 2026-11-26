import Darwin
import Foundation

/// The real `DoctorProbe`: the file system, `launchctl print` and the agent's socket.
/// Reads only.
public struct SystemDoctorProbe: DoctorProbe {
    /// Creates the probe.
    public init() {}

    /// The file's bytes, or nil.
    public func contents(of path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    /// Whether an executable file is at `path`.
    public func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// Whether anything is at `path` (a dangling symlink counts as nothing).
    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// `path` with symlinks resolved, as far as it exists.
    public func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// `launchctl print gui/<uid>/<label>`, read.
    public func launchAgentState(label: String) -> LaunchAgentState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unknown(String(describing: error))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return LaunchAgentState(
            launchctlStatus: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Asks the agent with `AgentClient`.
    public func queryAgent(socketPath: String, timeout: TimeInterval) -> AgentReply {
        AgentClient.status(socketPath: URL(fileURLWithPath: socketPath), timeout: timeout)
    }
}

extension LaunchAgentState {
    /// The state from `launchctl print`'s exit status and output: 113 means launchd
    /// doesn't know the service; otherwise the service's own `state =` and `pid =` lines
    /// (one tab deep; nested blocks have their own).
    init(launchctlStatus: Int32, output: String) {
        guard launchctlStatus == 0 else {
            self = launchctlStatus == 113 ? .notLoaded : .unknown("launchctl print exited with \(launchctlStatus)")
            return
        }
        var state: String?
        var pid: Int?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let text = line.dropFirst()
            if text.hasPrefix("state = ") { state = String(text.dropFirst("state = ".count)) }
            if text.hasPrefix("pid = ") { pid = Int(text.dropFirst("pid = ".count)) }
        }
        if state == "running", let pid {
            self = .running(pid: pid)
        } else if state != nil {
            self = .notRunning
        } else {
            self = .unknown("launchctl print showed no state")
        }
    }
}
