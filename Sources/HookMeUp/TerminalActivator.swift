import AgentKit
import AppKit
import HookMeUpCore

/// Brings a session forward when its notification is clicked: Terminal and iTerm2
/// select the exact tab by tty (AppleScript; macOS asks for Automation permission once);
/// Ghostty (1.3 or later, with its AppleScript on) focuses the one terminal whose working
/// directory is the session's folder (AppleScript too: one script lists the terminals,
/// a second focuses one by id; the folder never goes into a script), and only comes
/// forward when no single terminal is there, the scripts fail or Automation isn't allowed;
/// VS Code, VS Code Insiders, Cursor and Windsurf focus the open window that holds the
/// session's folder (by opening exactly that window's folder or workspace file), and are
/// only brought forward when no open window holds it, so a click never opens a new
/// window; other apps (Zed, Warp, Claude desktop…) come forward.
///
/// Activation is cooperative (macOS 14): the notification click makes this app active,
/// and it yields to the target app; macOS may still refuse, which the log shows. An app
/// that is asked over AppleScript (Terminal, iTerm2, Ghostty) activates itself. Logs say
/// what really happened (the strategy, the result and the frontmost app shortly after),
/// never a path. This is the only place the agent activates another app on purpose.
///
/// The app lookup and the plan (process, file and window-list reads) run off the main
/// thread; opening and activating run on it.
@MainActor
struct TerminalActivator: TerminalActivating {
    func open(_ place: SessionPlace) {
        DispatchQueue.global(qos: .userInitiated).async {
            let decision = Self.decide(place)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.carryOut(decision) }
            }
        }
    }

    /// The app that runs the session and how to bring it forward.
    nonisolated private static func decide(
        _ place: SessionPlace
    ) -> (owner: TerminalMapping.Owner, plan: SessionActivation)? {
        guard let owner = TerminalLookup.owner(hint: place.terminal) else { return nil }
        let plan = SessionActivation.plan(
            ownerBundleID: owner.bundleID, tty: place.terminal.tty, folder: place.folder,
            home: HookMeUpPaths.homeDirectory.path, fileSystem: LocalFileSystem(),
            resolve: LocalFileSystem.resolvingSymlinks,
            sessionAlive: SessionProbe.isAlive(place.terminal.ancestorPIDs.first),
            openWindowCount: { SessionProbe.normalWindowCount(of: owner.pid) })
        return (owner, plan)
    }

    private static func carryOut(_ decision: (owner: TerminalMapping.Owner, plan: SessionActivation)?) {
        guard let (owner, plan) = decision else {
            AgentLog.info("open session: no terminal app found in the process tree")
            return
        }
        switch plan {
        case .selectTab(let app, let tty):
            selectTab(app, tty: tty, owner: owner)
        case .focusTerminalByFolder(_, let folder):
            focusGhosttyTerminal(folder: folder, owner: owner)
        case .focusWindow(let target):
            focusWindow(target, owner: owner)
        case .activateApp where EditorWindows.tracksWindows(bundleID: owner.bundleID):
            bringForward(owner, strategy: "no matching window or no window state; brought the editor forward")
        case .activateApp, .none:
            bringForward(owner)
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

    /// What happened when Ghostty was asked for the session's terminal.
    enum GhosttyResult: Equatable {
        /// The one terminal in the folder was focused.
        case focused
        /// Ghostty listed its terminals, but not exactly one is in the folder (this many are).
        case noUniqueMatch(Int)
        /// A script failed: Ghostty before 1.3, its AppleScript off, Automation not allowed,
        /// the terminal gone, or a timeout.
        case scriptFailed
    }

    /// Ghostty: focuses the terminal in the session's folder, then brings Ghostty forward.
    private static func focusGhosttyTerminal(folder: String, owner: TerminalMapping.Owner) {
        // osascript can block (macOS asks for Automation permission the first time): off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ghosttyFocus(folder: folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .focused:
                        AgentLog.info("open session: ghostty terminal focused")
                        bringForward(owner)
                    case .noUniqueMatch(let count):
                        bringForward(owner, strategy: "ghostty: no unique match (\(count)); brought Ghostty forward")
                    case .scriptFailed:
                        bringForward(owner, strategy: "ghostty script failed; brought Ghostty forward")
                    }
                }
            }
        }
    }

    /// Lists Ghostty's terminals, and focuses the one whose working directory is `folder`
    /// when exactly one is. When none or several are, asks Ghostty to come forward (it
    /// answered the list, so Automation is allowed). Blocks: run it off the main thread.
    nonisolated static func ghosttyFocus(folder: String) -> GhosttyResult {
        guard let output = runAppleScriptOutput(GhosttyTerminals.list) else { return .scriptFailed }
        let terminals = GhosttyTerminals.terminals(fromList: output)
        switch GhosttyTerminals.match(folder: folder, in: terminals, resolve: LocalFileSystem.resolvingSymlinks) {
        case .unique(let id):
            guard let focus = GhosttyTerminals.focus(id: id), runAppleScript(focus) else { return .scriptFailed }
            return .focused
        case .none:
            _ = runAppleScript(GhosttyTerminals.activate)
            return .noUniqueMatch(0)
        case .several(let count):
            _ = runAppleScript(GhosttyTerminals.activate)
            return .noUniqueMatch(count)
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

    /// Runs `source` with /usr/bin/osascript (killed after `timeout` seconds); true when it
    /// printed "found". `arguments` go to the script's `on run argv`, never into its text.
    nonisolated static func runAppleScript(
        _ source: String, arguments: [String] = [], timeout: TimeInterval = 10
    ) -> Bool {
        let text = runAppleScriptOutput(source, arguments: arguments, timeout: timeout)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
    }

    nonisolated static func runAppleScript(_ command: GhosttyTerminals.Command) -> Bool {
        runAppleScript(command.source, arguments: command.arguments)
    }

    nonisolated static func runAppleScriptOutput(_ command: GhosttyTerminals.Command) -> String? {
        runAppleScriptOutput(command.source, arguments: command.arguments)
    }

    /// What `source` printed, run with /usr/bin/osascript and `arguments` (after `--`, so
    /// one that starts with "-" is not taken for an option); nil when it failed or ran
    /// longer than `timeout` seconds (then it is killed). The output is read while the
    /// script runs, so a long one can't fill the pipe and block it.
    nonisolated static func runAppleScriptOutput(
        _ source: String, arguments: [String] = [], timeout: TimeInterval = 10
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source, "--"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }  // set before run: no missed exit
        do { try process.run() } catch { return nil }
        let collected = CollectedOutput()
        let reading = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: reading) {
            collected.data = output.fileHandleForReading.readDataToEndOfFile()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = reading.wait(timeout: .now() + 1)
            return nil
        }
        // osascript has exited, so its end of the pipe is closed: the read ends.
        guard reading.wait(timeout: .now() + 1) == .success, process.terminationStatus == 0 else { return nil }
        return String(decoding: collected.data, as: UTF8.self)
    }
}

/// The output a reader thread collected; read only after the reading group finished.
private final class CollectedOutput: @unchecked Sendable {
    var data = Data()
}
