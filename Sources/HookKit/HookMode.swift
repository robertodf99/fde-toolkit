import Foundation

/// What one hook invocation does, from its first command-line argument.
public enum HookMode: Equatable, Sendable {
    /// PermissionRequest: ask the agent and wait. `timeout` is the handler timeout
    /// configured in Claude Code's settings for this hook.
    case permission(timeout: TimeInterval)
    /// Notification (elicitation_dialog): a "waiting for your reply" entry.
    case notify
    /// Stop: a "finished" entry with a gist of Claude's last message.
    case finished
    /// UserPromptSubmit / SessionEnd: clear the session's entries.
    case clear
}
