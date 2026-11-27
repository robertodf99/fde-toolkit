/// The terminal identifier inherited from Herdr Core.
public enum HerdrTerminal {
    /// Keeps only 1–64 ASCII letters, digits, underscores or hyphens.
    public static func validID(_ value: String?) -> String? {
        guard let value, (1...64).contains(value.utf8.count),
            value.utf8.allSatisfy({ byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                    || byte == 95 || byte == 45
            })
        else { return nil }
        return value
    }
}
