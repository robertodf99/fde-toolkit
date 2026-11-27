import Foundation
import HookMeUpCore

/// Command line of `hook-me-up`:
///   permission [--timeout <seconds>] | notify | finished | clear   [--socket <path>]
/// `--timeout` is the handler timeout from the settings (default 600, clamped to 1…600). `--socket` is
/// for self-tests only. Anything unexpected parses to nil (the hook prints nothing).
public struct HookInvocation: Equatable, Sendable {
    /// What to do.
    public var mode: HookMode
    /// A socket other than the default (self-tests only).
    public var socketPath: URL?
    /// Protocol of the CLI invoking this hook.
    public var client: HookClient

    /// Creates an invocation.
    public init(mode: HookMode, socketPath: URL?, client: HookClient = .claude) {
        self.mode = mode
        self.socketPath = socketPath
        self.client = client
    }

    /// Parses the arguments after the program name; nil for anything unexpected.
    public static func parse(_ arguments: [String]) -> HookInvocation? {
        guard let command = arguments.first else { return nil }
        var timeout = HookTiming.defaultHandlerTimeout
        var socketPath: URL?
        var client = HookClient.claude
        var index = 1
        while index < arguments.count {
            guard index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--timeout":
                guard command == "permission", let seconds = Double(value), seconds.isFinite else { return nil }
                timeout = min(max(seconds, 1), HookTiming.defaultHandlerTimeout)  // clamp to 1…600
            case "--client":
                guard let parsed = HookClient(rawValue: value) else { return nil }
                client = parsed
            case "--socket":
                guard !value.isEmpty else { return nil }
                socketPath = URL(fileURLWithPath: value)
            default:
                return nil
            }
            index += 2
        }
        switch command {
        case "permission":
            return HookInvocation(mode: .permission(timeout: timeout), socketPath: socketPath, client: client)
        case "notify": return HookInvocation(mode: .notify, socketPath: socketPath, client: client)
        case "finished": return HookInvocation(mode: .finished, socketPath: socketPath, client: client)
        case "clear": return HookInvocation(mode: .clear, socketPath: socketPath, client: client)
        default: return nil
        }
    }
}
