/// What a settings document holds of Hook Me Up's hooks (`SettingsMerger.inspect`), for
/// `hook-me-up-setup doctor` and the installer's warnings.
public struct HookInspection: Equatable, Sendable {
    /// The events, among the five, that run the expected hook with the expected arguments.
    public var installed: [String]
    /// The events, among the five, that don't.
    public var missing: [String]
    /// Events that run a hook-me-up handler more than once: each one notifies twice.
    public var duplicated: [String]
    /// hook-me-up handlers at another path (another installation), as written, sorted.
    public var otherPaths: [String]
    /// `"disableAllHooks": true`: Claude Code runs no hooks at all.
    public var allHooksDisabled: Bool

    /// Creates an inspection result.
    public init(
        installed: [String], missing: [String], duplicated: [String], otherPaths: [String], allHooksDisabled: Bool
    ) {
        self.installed = installed
        self.missing = missing
        self.duplicated = duplicated
        self.otherPaths = otherPaths
        self.allHooksDisabled = allHooksDisabled
    }
}
