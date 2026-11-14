import Foundation

/// The JSON a Claude Code hook receives on stdin (any event we subscribe to).
///
/// `session_id`, `cwd` and `hook_event_name` are required non-empty strings; anything
/// else that is missing or has an unexpected type is treated as absent. The whole
/// decoded document stays available in `raw`.
public struct HookInput: Sendable, Equatable {
    /// `session_id`.
    public let sessionID: String
    /// `cwd`: the session's working folder.
    public let cwd: String
    /// `hook_event_name`, e.g. "PermissionRequest".
    public let hookEventName: String
    /// `permission_mode`.
    public let permissionMode: String?
    /// `transcript_path`.
    public let transcriptPath: String?
    /// `tool_name` (PermissionRequest).
    public let toolName: String?
    /// `tool_input` (PermissionRequest).
    public let toolInput: JSONValue?
    /// `permission_suggestions`, well-formed entries only.
    public let permissionSuggestions: [PermissionUpdate]
    /// `mcp_server`, for MCP tools.
    public let mcpServer: JSONValue?
    /// `agent_id`: set when a subagent asks.
    public let agentID: String?
    /// `agent_type`.
    public let agentType: String?
    /// `message` (Notification).
    public let message: String?
    /// `title` (Notification).
    public let title: String?
    /// `notification_type` (Notification).
    public let notificationType: String?
    /// `reason` (SessionEnd).
    public let reason: String?
    /// The whole decoded input.
    public let raw: JSONValue

    /// Parses a hook's stdin; throws `HookInputError` without the required fields.
    public static func parse(_ data: Data) throws -> HookInput {
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = raw.objectValue else { throw HookInputError.notAnObject }

        func required(_ key: String) throws -> String {
            guard let value = object[key]?.stringValue, !value.isEmpty else {
                throw HookInputError.missingField(key)
            }
            return value
        }
        func optional(_ key: String) -> String? { object[key]?.stringValue }

        // A malformed suggestion is dropped on its own (it could never be applied
        // anyway), instead of failing the whole input and hiding the request.
        let suggestions = object["permission_suggestions"]?.arrayValue?.compactMap(PermissionUpdate.init(json:)) ?? []

        let mcpServer: JSONValue?
        if case .object? = object["mcp_server"] { mcpServer = object["mcp_server"] } else { mcpServer = nil }

        return HookInput(
            sessionID: try required("session_id"),
            cwd: try required("cwd"),
            hookEventName: try required("hook_event_name"),
            permissionMode: optional("permission_mode"),
            transcriptPath: optional("transcript_path"),
            toolName: optional("tool_name"),
            toolInput: object["tool_input"],
            permissionSuggestions: suggestions,
            mcpServer: mcpServer,
            agentID: optional("agent_id"),
            agentType: optional("agent_type"),
            message: optional("message"),
            title: optional("title"),
            notificationType: optional("notification_type"),
            reason: optional("reason"),
            raw: raw
        )
    }
}
