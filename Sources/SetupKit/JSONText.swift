import Foundation

/// Facts about JSON *text* that a decoded `JSONValue` no longer has: the order of the
/// top-level keys and the exact number literals (before they become Doubles).
enum JSONText {
    /// Keys of the top-level object in file order; nil when the text is not an object.
    static func topLevelKeys(_ text: String) -> [String]? {
        var keys: [String] = []
        var depth = 0
        var sawObject = false
        scan(text) { token in
            switch token {
            case .open(let bracket):
                if depth == 0 { sawObject = bracket == "{" }
                depth += 1
            case .close:
                depth -= 1
            case .string(let raw, let followedByColon):
                if depth == 1, sawObject, followedByColon { keys.append(decodeString(raw)) }
            case .number:
                break
            }
        }
        return sawObject ? keys : nil
    }

    /// Every number literal outside strings, as written.
    static func numberLiterals(_ text: String) -> [String] {
        var numbers: [String] = []
        scan(text) { if case .number(let literal) = $0 { numbers.append(literal) } }
        return numbers
    }

    /// True when a literal cannot be held exactly by a Double integer (beyond ±2^53).
    static func isUnsafeNumber(_ literal: String) -> Bool {
        let isInteger = !literal.contains(where: { ".eE".contains($0) })
        if isInteger {
            var digits = literal.hasPrefix("-") ? String(literal.dropFirst()) : literal
            while digits.count > 1, digits.hasPrefix("0") { digits.removeFirst() }
            let limit = "9007199254740992"  // 2^53
            return digits.count > limit.count || (digits.count == limit.count && digits > limit)
        }
        guard let value = Double(literal), value.isFinite else { return true }
        return abs(value) > 9_007_199_254_740_992
    }

    private enum Token {
        case open(Character)
        case close
        case string(raw: String, followedByColon: Bool)
        case number(String)
    }

    private static func scan(_ text: String, _ handle: (Token) -> Void) {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            switch char {
            case "{", "[":
                handle(.open(char))
                index += 1
            case "}", "]":
                handle(.close)
                index += 1
            case "\"":
                var raw = ""
                index += 1
                while index < chars.count, chars[index] != "\"" {
                    if chars[index] == "\\", index + 1 < chars.count {
                        raw.append(chars[index])
                        index += 1
                    }
                    raw.append(chars[index])
                    index += 1
                }
                index += 1  // closing quote
                var look = index
                while look < chars.count, chars[look].isWhitespace { look += 1 }
                handle(.string(raw: raw, followedByColon: look < chars.count && chars[look] == ":"))
            case "-", "0"..."9":
                var literal = ""
                while index < chars.count, "+-.eE0123456789".contains(chars[index]) {
                    literal.append(chars[index])
                    index += 1
                }
                handle(.number(literal))
            default:
                index += 1
            }
        }
    }

    private static func decodeString(_ raw: String) -> String {
        (try? JSONDecoder().decode(String.self, from: Data("\"\(raw)\"".utf8))) ?? raw
    }
}
