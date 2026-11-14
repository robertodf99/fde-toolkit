import AgentKit
import AppKit
import HookMeUpCore

/// "Open session": brings the session's terminal forward. Terminal and iTerm2 select
/// the exact tab by tty (AppleScript; asks for Automation permission once); Ghostty,
/// Warp, VS Code, Cursor and Claude desktop get app-level activation. This is the only
/// place the agent activates another app on purpose.
@MainActor
struct TerminalActivator: TerminalActivating {
    func activate(_ hint: TerminalHint) {
        Self.activate(hint: hint)
    }

    private static func activate(hint: TerminalHint) {
        guard let owner = TerminalLookup.owner(hint: hint) else {
            AgentLog.info("open session: no terminal app found in the process tree")
            return
        }
        guard let app = TerminalApp(bundleID: owner.bundleID), app.selectsTabByTTY, let tty = hint.tty,
            let source = TerminalScripts.selectTab(app, tty: tty)
        else {
            activateApp(owner)
            return
        }
        // AppleScript can block (e.g. while macOS asks for Automation permission): run it
        // with osascript off the main thread so the socket and notifications never stall.
        DispatchQueue.global(qos: .userInitiated).async {
            let found = runAppleScript(source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if found {
                        AgentLog.info("open session: selected the tab in \(owner.bundleID)")
                    } else {
                        AgentLog.info("open session: tab not selected; activating the app")
                        activateApp(owner)
                    }
                }
            }
        }
    }

    private static func activateApp(_ owner: TerminalMapping.Owner) {
        let running =
            NSRunningApplication(processIdentifier: owner.pid)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: owner.bundleID).first
        running?.activate()
        AgentLog.info("open session: activated \(owner.bundleID)")
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
