import Foundation

/// Finds and focuses the Ghostty terminal that runs a session, through Ghostty's
/// AppleScript (Ghostty 1.3 or later, on by default; `macos-applescript = false` turns it
/// off): one script lists every terminal's id and working directory, `match` picks the
/// one whose working directory is the session's folder, and a second script focuses it
/// by id. The scripts are fixed text: the folder never goes into a script, and the id
/// goes to the second one as an argument (`on run argv`), only after `isValidID`.
///
/// When several terminals are in the folder (splits or tabs there), Ghostty's AppleScript
/// can't tell which runs the session (it shows a terminal's id, title and working
/// directory, not its tty). Then the session's own tty gets a title marker: a random
/// token written as an OSC 2 title (`titleSequence`); `findMarker` asks Ghostty which
/// terminal shows it, `marked` keeps it only when exactly one of the folder's terminals
/// does, and the terminal's earlier title (listed by `titles`) is written back. The token
/// goes to the script as an argument too; the tty is never part of a script.
public enum GhosttyTerminals {
    /// Ghostty's bundle identifier.
    public static let bundleID = "com.mitchellh.ghostty"

    /// A script to run with its arguments (the run handler's `argv`).
    public struct Command: Equatable, Sendable {
        /// The AppleScript source, always one of the fixed scripts below.
        public let source: String
        /// Passed to `on run argv`, never part of `source`.
        public let arguments: [String]
    }

    /// Prints one line per terminal: its id, a tab and its working directory. A terminal
    /// whose working directory is unknown or holds a line break is left out, so every
    /// line is one terminal. Prints nothing when Ghostty isn't running (it is not started).
    public static let list = Command(
        source: """
            on run argv
              if not (application id "com.mitchellh.ghostty" is running) then return ""
              set output to ""
              tell application id "com.mitchellh.ghostty"
                -- Each item names its terminal by id, so its id and folder always go together.
                set allTerminals to every terminal
                repeat with t in allTerminals
                  set wd to working directory of t
                  if wd is not "" and wd does not contain (character id 10) and wd does not contain (character id 13) then
                    set output to output & (id of t) & (character id 9) & wd & (character id 10)
                  end if
                end repeat
              end tell
              return output
            end run
            """, arguments: [])

    /// Focuses the terminal whose id is `argv`'s first item: Ghostty brings its window to
    /// the front and activates itself. Prints "found", or "missing" when no terminal has
    /// that id any more.
    static let focusSource = """
        on run argv
          set wanted to item 1 of argv
          if not (application id "com.mitchellh.ghostty" is running) then return "missing"
          tell application id "com.mitchellh.ghostty"
            set matches to every terminal whose id is wanted
            if (count of matches) is 0 then return "missing"
            focus (item 1 of matches)
          end tell
          return "found"
        end run
        """

    /// Asks Ghostty to bring itself forward (used when no single terminal matches, once
    /// the list showed that Ghostty answers). Prints "found".
    public static let activate = Command(
        source: """
            on run argv
              if not (application id "com.mitchellh.ghostty" is running) then return "missing"
              tell application id "com.mitchellh.ghostty" to activate
              return "found"
            end run
            """, arguments: [])

    /// The command that focuses the terminal `id`; nil for an id that isn't a plain
    /// Ghostty id.
    public static func focus(id: String) -> Command? {
        isValidID(id) ? Command(source: focusSource, arguments: [id]) : nil
    }

    /// Whether `id` looks like a Ghostty terminal id (a UUID): 1 to 64 hexadecimal digits
    /// and dashes.
    public static func isValidID(_ id: String) -> Bool {
        (1...64).contains(id.count)
            && id.unicodeScalars.allSatisfy { $0.isASCII && ($0 == "-" || $0.properties.isASCIIHexDigit) }
    }

    /// A terminal as `list` prints it.
    public struct Terminal: Equatable, Sendable {
        /// Ghostty's id for the terminal.
        public let id: String
        /// Its working directory, as Ghostty reports it.
        public let workingDirectory: String

        /// Creates a terminal.
        public init(id: String, workingDirectory: String) {
            self.id = id
            self.workingDirectory = workingDirectory
        }
    }

    /// The terminals in `list`'s output. A line counts when it is an id that passes
    /// `isValidID`, a tab, and an absolute working directory; any other line is skipped.
    public static func terminals(fromList output: String) -> [Terminal] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> Terminal? in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let id = String(parts[0])
            let folder = String(parts[1])
            guard isValidID(id), folder.hasPrefix("/") else { return nil }
            return Terminal(id: id, workingDirectory: folder)
        }
    }

    /// Which terminal runs a session.
    public enum Match: Equatable, Sendable {
        /// Exactly one terminal is in the session's folder.
        case unique(id: String)
        /// None is.
        case none
        /// This many are (more than one): which one runs the session can't be told.
        case several(Int)
    }

    /// The terminal whose working directory is `folder` (absolute), when exactly one is.
    /// Paths are compared after `resolve` (symbolic links) and normalisation (`.`, `..`,
    /// trailing slashes, the `/private` prefix of /var, /tmp and /etc).
    public static func match(folder: String, in terminals: [Terminal], resolve: (String) -> String = { $0 }) -> Match {
        let ids = candidates(folder: folder, in: terminals, resolve: resolve)
        switch ids.count {
        case 0: return .none
        case 1: return .unique(id: ids[0])
        default: return .several(ids.count)
        }
    }

    /// The ids of the terminals whose working directory is `folder` (absolute), each once,
    /// in list order; compared as in `match`.
    public static func candidates(
        folder: String, in terminals: [Terminal], resolve: (String) -> String = { $0 }
    ) -> [String] {
        guard folder.hasPrefix("/") else { return [] }
        let session = EditorWindows.components(resolve(folder))
        var ids: [String] = []
        for terminal in terminals where terminal.workingDirectory.hasPrefix("/") && !ids.contains(terminal.id) {
            if EditorWindows.components(resolve(terminal.workingDirectory)) == session { ids.append(terminal.id) }
        }
        return ids
    }

    // MARK: Title marker

    /// Prints one line per terminal: its id, a tab and its title (`name`). A title with a
    /// line break is left out, so every line is one terminal; one that can't be read is
    /// skipped. Prints nothing when Ghostty isn't running (it is not started).
    public static let titles = Command(
        source: """
            on run argv
              if not (application id "com.mitchellh.ghostty" is running) then return ""
              set output to ""
              tell application id "com.mitchellh.ghostty"
                -- Each item names its terminal by id, so its id and title always go together.
                set allTerminals to every terminal
                repeat with t in allTerminals
                  try
                    set termTitle to name of t
                    if termTitle does not contain (character id 10) and termTitle does not contain (character id 13) then
                      set output to output & (id of t) & (character id 9) & termTitle & (character id 10)
                    end if
                  end try
                end repeat
              end tell
              return output
            end run
            """, arguments: [])

    /// Prints the id of each terminal whose title contains `argv`'s first item, one per
    /// line. Ghostty applies a title shortly after the terminal receives it, so it looks up
    /// to ten times, a tenth of a second apart (the delay runs outside the tell block), and
    /// prints nothing when no terminal shows it by then or Ghostty isn't running.
    static let findMarkerSource = """
        on run argv
          set wanted to item 1 of argv
          repeat 10 times
            if not (application id "com.mitchellh.ghostty" is running) then return ""
            set output to ""
            tell application id "com.mitchellh.ghostty"
              set allTerminals to every terminal
              repeat with t in allTerminals
                try
                  if (name of t) contains wanted then set output to output & (id of t) & (character id 10)
                end try
              end repeat
            end tell
            if output is not "" then return output
            delay 0.1
          end repeat
          return ""
        end run
        """

    /// The command that finds the terminals showing `token`; nil for a token that isn't one
    /// of `makeToken`'s.
    public static func findMarker(token: String) -> Command? {
        isValidToken(token) ? Command(source: findMarkerSource, arguments: [token]) : nil
    }

    /// The titles in `titles`' output, by terminal id. A line counts when it is an id that
    /// passes `isValidID`, a tab, and the title (which may be empty or hold tabs); the first
    /// line for an id wins.
    public static func terminalTitles(fromList output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, isValidID(String(parts[0])), result[String(parts[0])] == nil else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    /// The terminal ids in `findMarker`'s output, each once, in order; other lines are
    /// skipped.
    public static func ids(fromOutput output: String) -> [String] {
        var ids: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let id = String(line)
            if isValidID(id), !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// The terminal that shows the marker, when exactly one does and it is one of
    /// `candidates` (the terminals in the session's folder).
    public static func marked(ids: [String], candidates: [String]) -> String? {
        var seen: [String] = []
        for id in ids where !seen.contains(id) { seen.append(id) }
        guard seen.count == 1, candidates.contains(seen[0]) else { return nil }
        return seen[0]
    }

    /// A fresh marker: "hmu-" and 16 lowercase hexadecimal digits from `generator`.
    public static func makeToken(using generator: inout some RandomNumberGenerator) -> String {
        let digits = String(generator.next(), radix: 16)
        return "hmu-" + String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// Whether `token` has `makeToken`'s form exactly.
    public static func isValidToken(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard scalars.count == 20, token.hasPrefix("hmu-") else { return false }
        return scalars.dropFirst(4).allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// The bytes that set a terminal's title to `title` (sanitised first, see
    /// `sanitizedTitle`): OSC 2 (ESC ] 2 ;), the title in UTF-8, then BEL.
    public static func titleSequence(_ title: String) -> [UInt8] {
        [0x1B, 0x5D, 0x32, 0x3B] + Array(sanitizedTitle(title).utf8) + [0x07]
    }

    /// The longest title written back, in bytes of UTF-8.
    public static let maxTitleBytes = 255

    /// `title` without control characters (C0, DEL and C1: anything that could end the
    /// title sequence or start another one), cut to at most `maxTitleBytes` bytes of UTF-8
    /// between Unicode scalars.
    public static func sanitizedTitle(_ title: String) -> String {
        var result = String.UnicodeScalarView()
        var bytes = 0
        for scalar in title.unicodeScalars where scalar.properties.generalCategory != .control {
            let size = String(scalar).utf8.count
            guard bytes + size <= maxTitleBytes else { break }
            result.append(scalar)
            bytes += size
        }
        return String(result)
    }

    /// The device path of a session's tty, when it is a plain pseudo-terminal name:
    /// "ttys" and 3 or 4 ASCII digits, optionally after "/dev/" (e.g. "ttys003" gives
    /// "/dev/ttys003"). Anything else (other devices, other spellings, `..`) gives nil.
    public static func ttyDevicePath(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard name.hasPrefix("ttys") else { return nil }
        let digits = Array(name.unicodeScalars.dropFirst(4))
        guard (3...4).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return "/dev/" + name
    }
}
