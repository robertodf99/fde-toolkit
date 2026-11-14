/// One line of `hook-me-up-setup doctor`.
public struct DoctorCheck: Equatable, Sendable {
    /// How a check came out.
    public enum Result: String, Equatable, Sendable {
        /// As it should be.
        case pass
        /// Works, but something is worth fixing.
        case warn
        /// Hook Me Up can't work this way; the doctor exits 1.
        case fail
        /// Not checked (the reason is in `detail`).
        case skipped
        /// Worth knowing, nothing to fix.
        case info
    }

    /// What was checked, e.g. "Hooks".
    public var name: String
    /// How it came out.
    public var result: Result
    /// What was found.
    public var detail: String
    /// What to do about it, for warnings and failures (and some notes).
    public var fix: String?

    /// Creates a check line.
    public init(_ name: String, _ result: Result, _ detail: String, fix: String? = nil) {
        self.name = name
        self.result = result
        self.detail = detail
        self.fix = fix
    }
}

/// Everything the doctor found.
public struct DoctorReport: Equatable, Sendable {
    /// The checks, in the order they ran.
    public var checks: [DoctorCheck]

    /// Creates a report.
    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }

    /// 1 when any check failed; warnings don't fail.
    public var exitCode: Int32 { checks.contains { $0.result == .fail } ? 1 : 0 }

    /// The check named `name`, if it ran.
    public func check(_ name: String) -> DoctorCheck? {
        checks.first { $0.name == name }
    }

    /// The report as printed: one line per check, its fix indented below, and a summary.
    public func rendered() -> String {
        var lines: [String] = []
        for check in checks {
            let tag =
                switch check.result {
                case .pass: "PASS"
                case .warn: "WARN"
                case .fail: "FAIL"
                case .skipped: "SKIP"
                case .info: "INFO"
                }
            lines.append("\(tag)  \(check.name): \(check.detail)")
            if let fix = check.fix {
                let label = check.result == .info ? "Note" : "Fix"
                for (index, line) in fix.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    lines.append((index == 0 ? "      \(label): " : "        ") + line)
                }
            }
        }
        let failures = checks.filter { $0.result == .fail }.count
        let warnings = checks.filter { $0.result == .warn }.count
        lines.append("")
        if failures == 0, warnings == 0 {
            lines.append("No problems found.")
        } else {
            lines.append(
                "\(failures) problem\(failures == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s").")
        }
        return lines.joined(separator: "\n")
    }
}
