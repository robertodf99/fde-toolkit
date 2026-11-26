import Foundation

/// AppleScript that selects the tab (and window) of a tty in Terminal or iTerm2. The
/// tty is validated strictly before it goes into the script text.
public enum TerminalScripts {
    /// The script for `app` and `tty` (e.g. "ttys003"); nil for an app without tab
    /// selection or a tty that is not a plain terminal device name.
    public static func selectTab(_ app: TerminalApp, tty: String) -> String? {
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard name.hasPrefix("tty"), (4...12).contains(name.count),
            name.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        else { return nil }
        let device = "/dev/" + name
        switch app {
        case .appleTerminal:
            return """
                tell application "Terminal"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if tty of t is "\(device)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "found"
                      end if
                    end repeat
                  end repeat
                end tell
                return "missing"
                """
        case .iTerm2:
            return """
                tell application "iTerm2"
                  repeat with w in windows
                    repeat with t in tabs of w
                      repeat with s in sessions of t
                        if tty of s is "\(device)" then
                          select w
                          tell t to select
                          tell s to select
                          activate
                          return "found"
                        end if
                      end repeat
                    end repeat
                  end repeat
                end tell
                return "missing"
                """
        default:
            return nil
        }
    }
}
