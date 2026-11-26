import Foundation

/// How long the hook waits.
enum HookTiming {
    /// Claude Code kills a hook at its handler timeout. The hook gives up this much
    /// earlier, tells the agent (`timedOut`) and prints nothing (handler timeout 600 s,
    /// self-exit at 590 s).
    static let selfExitMargin: TimeInterval = 10
    /// The handler timeout the installer configures, and the longest the hook accepts.
    static let defaultHandlerTimeout: TimeInterval = 600
    static let permissionConnectTimeout: TimeInterval = 0.3
    static let fireAndForgetConnectTimeout: TimeInterval = 0.2

    /// When the hook gives up for a given handler timeout (at least 1 s).
    static func selfExitDelay(handlerTimeout: TimeInterval) -> TimeInterval {
        max(1, handlerTimeout - selfExitMargin)
    }
}
