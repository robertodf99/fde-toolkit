// Claude Code hook entry point. Always exits 0. Prints a decision only when runHook
// returns one; on any error, mismatch, timeout or pause it prints nothing, so Claude
// Code falls back to its own terminal dialog.
import Darwin
import Foundation
import HookKit
import HookMeUpCore

signal(SIGPIPE, SIG_IGN)
// Ended by a signal (Claude Code interrupts the hook, or the session ends): leave
// quietly with status 0 and no output. _exit is async-signal-safe.
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber) { _ in _exit(0) }
}

let maxStdinBytes = 16 << 20

guard let invocation = HookInvocation.parse(Array(CommandLine.arguments.dropFirst())) else { exit(0) }

var stdinData = Data()
while let chunk = try? FileHandle.standardInput.read(upToCount: 64 * 1024), !chunk.isEmpty {
    stdinData.append(chunk)
    if stdinData.count > maxStdinBytes { exit(0) }
}

if let output = runHook(
    mode: invocation.mode, stdin: stdinData,
    socketPath: invocation.socketPath ?? HookMeUpPaths.defaultSocketURL)
{
    try? FileHandle.standardOutput.write(contentsOf: output + Data("\n".utf8))
}
exit(0)
