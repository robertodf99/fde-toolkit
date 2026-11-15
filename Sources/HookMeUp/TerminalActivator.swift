import AgentKit
import AppKit
import HookMeUpCore

/// Brings a session forward when its notification is clicked: Terminal and iTerm2
/// select the exact tab by tty (AppleScript; macOS asks for Automation permission once);
/// Ghostty (1.3 or later, with its AppleScript on) focuses the one terminal whose working
/// directory is the session's folder (AppleScript too: one script lists the terminals,
/// a second focuses one by id; the folder never goes into a script). When several
/// terminals are in the folder, a title marker written to the session's own tty tells
/// which one runs it (see `ghosttyFocus`); Ghostty only comes forward when no terminal is
/// there, the marker isn't seen, the tty can't be used, the scripts fail or Automation
/// isn't allowed. VS Code, VS Code Insiders, Cursor and Windsurf focus the open window
/// that holds the session's folder (by opening exactly that window's folder or workspace
/// file), and are only brought forward when no open window holds it, so a click never
/// opens a new window; with Hook Me Up's editor extension installed, the window that has
/// the session's terminal also shows it (see `EditorExtension`). Other apps (Zed, Warp,
/// Claude desktop…) come forward.
///
/// Activation is cooperative (macOS 14): the notification click makes this app active,
/// and it yields to the target app; macOS may still refuse, which the log shows. An app
/// that is asked over AppleScript (Terminal, iTerm2, Ghostty) activates itself. Logs say
/// what really happened (the strategy, the result and the frontmost app shortly after),
/// never a path, a title, a tty or a token. This is the only place the agent activates
/// another app on purpose.
///
/// The app lookup, the plan (process, file and window-list reads) and the editor request
/// run off the main thread; opening and activating run on it.
@MainActor
struct TerminalActivator: TerminalActivating {
    func open(_ place: SessionPlace) {
        DispatchQueue.global(qos: .userInitiated).async {
            let decision = Self.decide(place)
            // Before the window is focused, so the extension finds the request when it does.
            let asked = decision?.editorRequest.map {
                EditorRequestFile.write($0, to: HookMeUpPaths.editorFocusRequestURL(home: HookMeUpPaths.homeDirectory))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.carryOut(decision, askedEditor: asked) }
            }
        }
    }

    /// The app that runs a session, how to bring it forward, and what else the click needs.
    struct Decision: Sendable {
        let owner: TerminalMapping.Owner
        let plan: SessionActivation
        /// The session's process (the nearest ancestor): its controlling terminal is the only
        /// one a title marker may be written to.
        let sessionPID: pid_t?
        /// The request for the editor extension, when it should be asked (see
        /// `EditorExtension.shouldAsk`).
        let editorRequest: Data?
    }

    nonisolated private static func decide(_ place: SessionPlace) -> Decision? {
        guard let owner = TerminalLookup.owner(hint: place.terminal) else { return nil }
        let home = HookMeUpPaths.homeDirectory.path
        let sessionPID = place.terminal.ancestorPIDs.first
        let alive = SessionProbe.isAlive(sessionPID)
        var windows: Int?
        let openWindowCount = { () -> Int in
            if let windows { return windows }
            let count = SessionProbe.normalWindowCount(of: owner.pid)
            windows = count
            return count
        }
        let plan = SessionActivation.plan(
            ownerBundleID: owner.bundleID, tty: place.terminal.tty, folder: place.folder, home: home,
            fileSystem: LocalFileSystem(), resolve: LocalFileSystem.resolvingSymlinks, sessionAlive: alive,
            openWindowCount: openWindowCount)
        var request: Data?
        if EditorExtension.shouldAsk(
            plan: plan, bundleID: owner.bundleID, sessionAlive: alive, openWindowCount: openWindowCount,
            isInstalled: {
                EditorExtension.isInstalled(bundleID: owner.bundleID, home: home, fileSystem: LocalFileSystem())
            })
        {
            var generator = SystemRandomNumberGenerator()
            request = EditorExtension.request(
                pids: place.terminal.ancestorPIDs, editorPID: owner.pid,
                nonce: EditorExtension.makeNonce(using: &generator), now: Date())
        }
        return Decision(owner: owner, plan: plan, sessionPID: sessionPID, editorRequest: request)
    }

    /// `askedEditor`: whether the editor request was written (nil: none was due).
    private static func carryOut(_ decision: Decision?, askedEditor: Bool?) {
        guard let decision else {
            AgentLog.info("open session: no terminal app found in the process tree")
            return
        }
        let owner = decision.owner
        if let askedEditor {
            AgentLog.info(
                "open session: \(askedEditor ? "asked" : "could not ask") \(owner.bundleID) to show the session's terminal"
            )
        }
        switch decision.plan {
        case .selectTab(let app, let tty):
            selectTab(app, tty: tty, owner: owner)
        case .focusTerminalByFolder(_, let folder, let tty):
            focusGhosttyTerminal(folder: folder, tty: tty, sessionPID: decision.sessionPID, owner: owner)
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
        /// Of several terminals in the folder, the one that showed the title marker was
        /// focused (after its title was written back).
        case focusedByMarker
        /// Ghostty listed its terminals, and none is in the folder (this many: 0).
        case noUniqueMatch(Int)
        /// This many terminals are in the folder, and not exactly one of them showed the
        /// marker in time (Ghostty set to ignore titles, `title = …`; the session changed its
        /// title first; or it appeared elsewhere).
        case markerNotSeen(Int)
        /// This many terminals are in the folder, and the session's tty can't be used: none
        /// known, the session has ended, or it is not the session's terminal any more.
        /// Nothing was written.
        case noUsableTTY(Int)
        /// A script failed: Ghostty before 1.3, its AppleScript off, Automation not allowed,
        /// the terminal gone, or a timeout.
        case scriptFailed
    }

    /// Ghostty: focuses the session's terminal, then brings Ghostty forward.
    private static func focusGhosttyTerminal(
        folder: String, tty: String?, sessionPID: pid_t?, owner: TerminalMapping.Owner
    ) {
        // osascript can block (macOS asks for Automation permission the first time): off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ghosttyFocus(folder: folder, using: .live(tty: tty, sessionPID: sessionPID))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .focused:
                        AgentLog.info("open session: ghostty terminal focused")
                        bringForward(owner)
                    case .focusedByMarker:
                        AgentLog.info("open session: ghostty terminal focused (title marker)")
                        bringForward(owner)
                    case .noUniqueMatch(let count):
                        bringForward(owner, strategy: "ghostty: no unique match (\(count)); brought Ghostty forward")
                    case .markerNotSeen(let count):
                        bringForward(
                            owner, strategy: "ghostty: title marker not seen (\(count)); brought Ghostty forward")
                    case .noUsableTTY(let count):
                        bringForward(owner, strategy: "ghostty: no usable tty (\(count)); brought Ghostty forward")
                    case .scriptFailed:
                        bringForward(owner, strategy: "ghostty script failed; brought Ghostty forward")
                    }
                }
            }
        }
    }

    /// What `ghosttyFocus` does outside itself: replaced in tests.
    struct GhosttyIO {
        /// Runs one of `GhosttyTerminals`' scripts; what it printed, or nil when it failed.
        var run: (GhosttyTerminals.Command) -> String?
        /// Writes bytes to the session's own terminal; false when that can't be done now.
        /// Nil when the session has no usable tty at all.
        var writeToSession: (([UInt8]) -> Bool)?
        /// A fresh marker (`GhosttyTerminals.makeToken`).
        var makeToken: () -> String
        /// Resolves symbolic links in a path.
        var resolve: (String) -> String

        /// The real thing: osascript, and `TTYWriter` on the device at `tty` while it is the
        /// controlling terminal of the session's live process `sessionPID` (checked again
        /// before every write).
        nonisolated static func live(tty: String?, sessionPID: pid_t?) -> GhosttyIO {
            let device = { () -> dev_t? in
                guard let sessionPID, SessionProbe.isAlive(sessionPID) else { return nil }
                return SessionProbe.controllingTTYDevice(of: sessionPID)
            }
            var write: (([UInt8]) -> Bool)?
            if let tty, device() != nil {
                write = { bytes in
                    guard let expected = device() else { return false }
                    return TTYWriter.write(bytes, toDevice: tty, expectedDevice: expected)
                }
            }
            return GhosttyIO(
                run: { runAppleScriptOutput($0) }, writeToSession: write,
                makeToken: {
                    var generator = SystemRandomNumberGenerator()
                    return GhosttyTerminals.makeToken(using: &generator)
                }, resolve: LocalFileSystem.resolvingSymlinks)
        }
    }

    /// Lists Ghostty's terminals, and focuses the one whose working directory is `folder`
    /// when exactly one is. When several are, the title marker tells which (see
    /// `focusMarked`). When none is, or the marker can't tell, asks Ghostty to come forward
    /// (it answered the list, so Automation is allowed). Blocks: run it off the main thread.
    nonisolated static func ghosttyFocus(folder: String, using io: GhosttyIO) -> GhosttyResult {
        guard let output = io.run(GhosttyTerminals.list) else { return .scriptFailed }
        let terminals = GhosttyTerminals.terminals(fromList: output)
        let candidates = GhosttyTerminals.candidates(folder: folder, in: terminals, resolve: io.resolve)
        switch candidates.count {
        case 0:
            _ = io.run(GhosttyTerminals.activate)
            return .noUniqueMatch(0)
        case 1:
            return focus(candidates[0], using: io) ? .focused : .scriptFailed
        default:
            return focusMarked(among: candidates, using: io)
        }
    }

    /// Several terminals in the folder: lists every terminal's title, writes a fresh token as
    /// the title of the session's own tty, asks Ghostty which terminal shows it, writes that
    /// terminal's earlier title back (sanitised; empty when it wasn't listed) before
    /// anything else, and focuses it when it is one of `candidates` and the only one that
    /// shows the token. Without a usable tty nothing is written; when the token isn't seen
    /// in exactly one terminal, nothing is written back (which title it replaced can't be
    /// told) and Ghostty only comes forward.
    nonisolated private static func focusMarked(among candidates: [String], using io: GhosttyIO) -> GhosttyResult {
        let count = candidates.count
        let comeForward = { (result: GhosttyResult) -> GhosttyResult in
            _ = io.run(GhosttyTerminals.activate)
            return result
        }
        guard let write = io.writeToSession else { return comeForward(.noUsableTTY(count)) }
        guard let listed = io.run(GhosttyTerminals.titles) else { return .scriptFailed }
        let titles = GhosttyTerminals.terminalTitles(fromList: listed)
        let token = io.makeToken()
        guard let find = GhosttyTerminals.findMarker(token: token) else { return comeForward(.markerNotSeen(count)) }
        guard write(GhosttyTerminals.titleSequence(token)) else { return comeForward(.noUsableTTY(count)) }
        let seen = GhosttyTerminals.ids(fromOutput: io.run(find) ?? "")
        if seen.count == 1 { _ = write(GhosttyTerminals.titleSequence(titles[seen[0]] ?? "")) }
        guard let id = GhosttyTerminals.marked(ids: seen, candidates: candidates) else {
            return comeForward(.markerNotSeen(count))
        }
        return focus(id, using: io) ? .focusedByMarker : .scriptFailed
    }

    /// Asks Ghostty to focus the terminal `id`; true when it did.
    nonisolated private static func focus(_ id: String, using io: GhosttyIO) -> Bool {
        guard let command = GhosttyTerminals.focus(id: id) else { return false }
        return io.run(command)?.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
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
