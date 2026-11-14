import Foundation

/// Command line of `hook-me-up`:
///   permission [--timeout <seconds>] | notify | finished | clear   [--socket <path>]
/// `--timeout` is the handler timeout from the settings (default 600, clamped to 1…600). `--socket` is
/// for self-tests only. Anything unexpected parses to nil (the hook prints nothing).
public struct HookInvocation: Equatable, Sendable {
    /// What to do.
    public var mode: HookMode
    /// A socket other than the default (self-tests only).
    public var socketPath: URL?

    /// Creates an invocation.
    public init(mode: HookMode, socketPath: URL?) {
        self.mode = mode
        self.socketPath = socketPath
    }

    /// Parses the arguments after the program name; nil for anything unexpected.
    public static func parse(_ arguments: [String]) -> HookInvocation? {
        guard let command = arguments.first else { return nil }
        var timeout = HookTiming.defaultHandlerTimeout
        var socketPath: URL?
        var index = 1
        while index < arguments.count {
            guard index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--timeout":
                guard command == "permission", let seconds = Double(value), seconds.isFinite else { return nil }
                timeout = min(max(seconds, 1), HookTiming.defaultHandlerTimeout)  // clamp to 1…600
            case "--socket":
                guard !value.isEmpty else { return nil }
                socketPath = URL(fileURLWithPath: value)
            default:
                return nil
            }
            index += 2
        }
        switch command {
        case "permission": return HookInvocation(mode: .permission(timeout: timeout), socketPath: socketPath)
        case "notify": return HookInvocation(mode: .notify, socketPath: socketPath)
        case "finished": return HookInvocation(mode: .finished, socketPath: socketPath)
        case "clear": return HookInvocation(mode: .clear, socketPath: socketPath)
        default: return nil
        }
    }
}
