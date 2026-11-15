import Foundation

/// Finds and focuses the Ghostty terminal that runs a session, through Ghostty's
/// AppleScript (Ghostty 1.3 or later, on by default; `macos-applescript = false` turns it
/// off): one script lists every terminal's id and working directory, `match` picks the
/// one whose working directory is the session's folder, and a second script focuses it
/// by id. The scripts are fixed text: the folder never goes into a script, and the id
/// goes to the second one as an argument (`on run argv`), only after `isValidID`.
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
        guard folder.hasPrefix("/") else { return .none }
        let session = EditorWindows.components(resolve(folder))
        var ids: [String] = []
        for terminal in terminals where terminal.workingDirectory.hasPrefix("/") && !ids.contains(terminal.id) {
            if EditorWindows.components(resolve(terminal.workingDirectory)) == session { ids.append(terminal.id) }
        }
        switch ids.count {
        case 0: return .none
        case 1: return .unique(id: ids[0])
        default: return .several(ids.count)
        }
    }
}
