import Foundation

/// One permission rule inside a permission update (`{toolName, ruleContent?}`).
public struct PermissionRule: Codable, Equatable, Sendable {
    /// The tool, e.g. "Bash".
    public var toolName: String
    /// The rule's argument, e.g. "npm test:*"; nil for the whole tool.
    public var ruleContent: String?

    /// Creates a rule.
    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }
}
