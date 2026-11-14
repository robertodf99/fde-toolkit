import Foundation

/// A rough, conservative reading of a shell command line for effect tags.
///
/// It is not a shell parser: it splits on control operators (outside quotes), strips
/// common wrappers (env assignments, sudo, env, xargs, ...) and records output
/// redirections. Warning tags may over-fire (e.g. an operator inside `$(...)` in double
/// quotes) rather than miss something.
struct ShellCommand {
    struct Segment {
        var words: [String]
        /// (operator, target) for output and input redirections.
        var redirects: [(op: String, target: String)]

        var name: String? { words.first.map { ($0 as NSString).lastPathComponent } }
        var args: [String] { Array(words.dropFirst()) }
    }

    let segments: [Segment]

    init(_ command: String) {
        var segments: [Segment] = []
        for raw in Self.tokenize(command) {
            var words: [String] = []
            var redirects: [(op: String, target: String)] = []
            var pendingRedirect: String?
            for token in raw {
                switch token {
                case .word(let word):
                    if let op = pendingRedirect {
                        redirects.append((op, word))
                        pendingRedirect = nil
                    } else {
                        words.append(word)
                    }
                case .redirect(let op, let target):
                    if let target { redirects.append((op, target)) } else { pendingRedirect = op }
                }
            }
            let stripped = Self.stripWrappers(words)
            if !stripped.isEmpty || !redirects.isEmpty {
                segments.append(Segment(words: stripped, redirects: redirects))
            }
        }
        self.segments = segments
    }

    // MARK: Tokenizer

    private enum Token {
        case word(String)
        /// A redirection; `target` is set for fd duplications like `2>&1` (never a file).
        case redirect(String, target: String?)
    }

    /// Returns the tokens of each segment (split on ; & && || | newline ( ) ` $( ).
    private static func tokenize(_ text: String) -> [[Token]] {
        var segments: [[Token]] = [[]]
        var word = ""
        var hasWord = false
        var inSingle = false
        var inDouble = false
        // Open command substitutions / subshells; `true` when opened inside double quotes,
        // so the closing ) or ` returns to the quoted string.
        enum Opener { case paren, backtick }
        var openers: [(kind: Opener, inDouble: Bool)] = []
        let chars = Array(text)
        var i = 0

        func flushWord() {
            if hasWord { segments[segments.count - 1].append(.word(word)) }
            word = ""
            hasWord = false
        }
        func newSegment() {
            flushWord()
            if !(segments.last?.isEmpty ?? true) { segments.append([]) }
        }

        while i < chars.count {
            let c = chars[i]
            if inSingle {
                if c == "'" { inSingle = false } else { word.append(c) }
                i += 1
                continue
            }
            if inDouble {
                if c == "$", i + 1 < chars.count, chars[i + 1] == "(" {
                    // Command substitution runs even inside double quotes: analyse it too.
                    openers.append((.paren, true))
                    inDouble = false
                    newSegment()
                    i += 2
                    continue
                } else if c == "`" {
                    openers.append((.backtick, true))
                    inDouble = false
                    newSegment()
                    i += 1
                    continue
                } else if c == "\"" {
                    inDouble = false
                } else if c == "\\", i + 1 < chars.count, "\"\\$`".contains(chars[i + 1]) {
                    word.append(chars[i + 1])
                    i += 1
                } else {
                    word.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case "'":
                inSingle = true
                hasWord = true
            case "\"":
                inDouble = true
                hasWord = true
            case "\\":
                if i + 1 < chars.count {
                    if chars[i + 1] != "\n" {
                        word.append(chars[i + 1])
                        hasWord = true
                    }
                    i += 1
                }
            case " ", "\t":
                flushWord()
            case "\n", ";", "|":
                newSegment()
            case "(":
                openers.append((.paren, false))
                newSegment()
            case "$" where i + 1 < chars.count && chars[i + 1] == "(":
                openers.append((.paren, false))
                newSegment()
                i += 1
            case ")":
                newSegment()
                if let last = openers.last, last.kind == .paren {
                    openers.removeLast()
                    inDouble = last.inDouble
                }
            case "`":
                newSegment()
                if let last = openers.last, last.kind == .backtick {
                    openers.removeLast()
                    inDouble = last.inDouble
                } else {
                    openers.append((.backtick, false))
                }
            case "&":
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    // &> or &>> : redirect both streams.
                    flushWord()
                    var op = "&>"
                    i += 1
                    if i + 1 < chars.count, chars[i + 1] == ">" {
                        op = "&>>"
                        i += 1
                    }
                    segments[segments.count - 1].append(.redirect(op, target: nil))
                } else {
                    newSegment()
                }
            case ">", "<":
                // A pure-digit word just before is the fd number (2>, 1>>).
                var op = ""
                if hasWord, !word.isEmpty, word.allSatisfy(\.isNumber) {
                    op = word
                    word = ""
                    hasWord = false
                } else {
                    flushWord()
                }
                op.append(c)
                if i + 1 < chars.count, chars[i + 1] == c {
                    op.append(c)
                    i += 1
                }
                if c == ">", i + 1 < chars.count, chars[i + 1] == "|" {
                    op.append("|")
                    i += 1
                }
                if i + 1 < chars.count, chars[i + 1] == "&" {
                    // fd duplication: >&2, 2>&1, <&- ; target is not a file.
                    i += 1
                    var target = "&"
                    while i + 1 < chars.count, chars[i + 1].isNumber || chars[i + 1] == "-" {
                        target.append(chars[i + 1])
                        i += 1
                    }
                    segments[segments.count - 1].append(.redirect(op, target: target))
                } else {
                    segments[segments.count - 1].append(.redirect(op, target: nil))
                }
            default:
                word.append(c)
                hasWord = true
            }
            i += 1
        }
        flushWord()
        return segments.filter { !$0.isEmpty }
    }

    // MARK: Wrappers

    private static let keywords: Set<String> = [
        "then", "do", "else", "elif", "if", "while", "until", "!", "{", "}", "fi", "done",
    ]

    /// Removes env assignments and wrapper commands so the real command comes first.
    private static func stripWrappers(_ input: [String]) -> [String] {
        var words = input
        var changed = true
        while changed, let first = words.first {
            changed = false
            if keywords.contains(first) || isAssignment(first) {
                words.removeFirst()
                changed = true
                continue
            }
            let name = (first as NSString).lastPathComponent
            switch name {
            case "sudo", "doas":
                words = dropFlags(words.dropFirst(), takingValue: ["-u", "-g", "-h", "-p", "-C", "-D", "-U"])
                changed = true
            case "env":
                var rest = dropFlags(words.dropFirst(), takingValue: ["-u", "-C", "-S", "-P"])
                while let next = rest.first, isAssignment(next) { rest.removeFirst() }
                words = rest
                changed = true
            case "command", "builtin", "exec", "nohup", "time", "caffeinate":
                words = dropFlags(words.dropFirst(), takingValue: [])
                changed = true
            case "nice":
                words = dropFlags(words.dropFirst(), takingValue: ["-n"])
                changed = true
            case "timeout", "gtimeout":
                var rest = dropFlags(words.dropFirst(), takingValue: ["-s", "-k", "--signal", "--kill-after"])
                if !rest.isEmpty { rest.removeFirst() }  // the duration
                words = rest
                changed = true
            case "xargs":
                words = dropFlags(
                    words.dropFirst(), takingValue: ["-I", "-n", "-P", "-L", "-d", "-s", "-E", "-J", "-R", "-S"])
                changed = true
            default:
                break
            }
        }
        return words
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return false }
        let name = word[..<eq]
        return name.first.map { $0 == "_" || $0.isLetter } == true
            && name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    private static func dropFlags(_ words: ArraySlice<String>, takingValue: Set<String>) -> [String] {
        var rest = Array(words)
        while let next = rest.first, next.hasPrefix("-"), next != "-" {
            rest.removeFirst()
            if next == "--" { break }
            if takingValue.contains(next), !rest.isEmpty { rest.removeFirst() }
        }
        return rest
    }
}
