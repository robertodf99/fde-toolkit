import AgentKit
import AppKit
import HookMeUpCore

/// Brings a session forward when its notification is clicked: Terminal and iTerm2
/// select the exact tab by tty (AppleScript; macOS asks for Automation permission once);
/// VS Code, VS Code Insiders, Cursor and Windsurf focus the open window that holds the
/// session's folder (by opening exactly that window's folder or workspace file), and are
/// only brought forward when no open window holds it, so a click never opens a new
/// window; other apps (Zed, Ghostty, Warp, Claude desktop…) come forward.
///
/// Activation is cooperative (macOS 14): the notification click makes this app active,
/// and it yields to the target app. Logs say what really happened (the strategy, the
/// result and the frontmost app shortly after), never a path. This is the only place the
/// agent activates another app on purpose.
@MainActor
struct TerminalActivator: TerminalActivating {
    func open(_ place: SessionPlace) {
        guard let owner = TerminalLookup.owner(hint: place.terminal) else {
            AgentLog.info("open session: no terminal app found in the process tree")
            return
        }
        let plan = SessionActivation.plan(
            ownerBundleID: owner.bundleID, tty: place.terminal.tty, folder: place.folder,
            home: FileManager.default.homeDirectoryForCurrentUser.path, fileSystem: LocalFileSystem(),
            resolve: LocalFileSystem.resolvingSymlinks)
        switch plan {
        case .selectTab(let app, let tty):
            Self.selectTab(app, tty: tty, owner: owner)
        case .focusWindow(let target):
            Self.focusWindow(target, owner: owner)
        case .activateApp where EditorWindows.tracksWindows(bundleID: owner.bundleID):
            Self.bringForward(owner, strategy: "no matching window; brought the editor forward")
        case .activateApp, .none:
            Self.bringForward(owner)
        }
    }

    private static func selectTab(_ app: TerminalApp, tty: String, owner: TerminalMapping.Owner) {
        guard let source = TerminalScripts.selectTab(app, tty: tty) else {
            bringForward(owner)
            return
        }
        // AppleScript can block (e.g. while macOS asks for Automation permission): run it
        // with osascript off the main thread so the socket and notifications never stall.
        DispatchQueue.global(qos: .userInitiated).async {
            let found = runAppleScript(source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AgentLog.info("open session: tab \(found ? "selected" : "not found") in \(owner.bundleID)")
                    bringForward(owner)
                }
            }
        }
    }

    /// Opens exactly the window's folder (or `.code-workspace` file) with the editor that
    /// runs the session, which focuses that existing window.
    private static func focusWindow(_ target: String, owner: TerminalMapping.Owner) {
        if let app = running(owner) { NSApp.yieldActivation(to: app) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: target)], withApplicationAt: URL(fileURLWithPath: owner.appPath),
            configuration: configuration
        ) { _, error in
            // Only the error's domain and code: its description may contain the path.
            let failure = error.map { error -> String in
                let error = error as NSError
                return "\(error.domain) \(error.code)"
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let failure {
                        AgentLog.info("open session: \(owner.bundleID) could not focus the window (\(failure))")
                        bringForward(owner)
                    } else {
                        AgentLog.info("open session: focused an existing window of \(owner.bundleID)")
                        reportFrontmost(expected: owner.bundleID)
                    }
                }
            }
        }
    }

    /// Brings the app forward with cooperative activation, falling back to a plain
    /// activation request. `strategy`, when given, starts the log line.
    private static func bringForward(_ owner: TerminalMapping.Owner, strategy: String? = nil) {
        let prefix = "open session: " + (strategy.map { "\($0); " } ?? "")
        guard let target = running(owner) else {
            AgentLog.info(prefix + "\(owner.bundleID) is not running")
            return
        }
        NSApp.yieldActivation(to: target)
        var accepted = target.activate(from: NSRunningApplication.current, options: [])
        if !accepted { accepted = target.activate() }
        AgentLog.info(prefix + "activating \(owner.bundleID) \(accepted ? "accepted" : "refused")")
        reportFrontmost(expected: owner.bundleID)
    }

    private static func running(_ owner: TerminalMapping.Owner) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: owner.pid)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: owner.bundleID).first
    }

    /// Logs which app is frontmost shortly after, to tell a real activation from one macOS
    /// ignored.
    private static func reportFrontmost(expected: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
                AgentLog.info(
                    "open session: frontmost is \(frontmost)" + (frontmost == expected ? "" : " (expected \(expected))")
                )
            }
        }
    }

    /// Runs `source` with /usr/bin/osascript (killed after 10 s); true when it printed "found".
    nonisolated static func runAppleScript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }  // set before run: no missed exit
        do { try process.run() } catch { return false }
        if finished.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            return false
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && text.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
    }
}
