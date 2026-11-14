import Foundation

/// Terminal apps the agent knows how to bring forward.
public enum TerminalApp: Equatable, Sendable {
    /// Terminal.
    case appleTerminal
    /// iTerm2.
    case iTerm2
    /// Ghostty.
    case ghostty
    /// Warp.
    case warp
    /// Visual Studio Code (integrated terminal).
    case vsCode
    /// Cursor (integrated terminal).
    case cursor
    /// The Claude desktop app.
    case claudeDesktop

    /// The terminal app with this bundle identifier, if it is one of the known ones.
    public init?(bundleID: String) {
        switch bundleID {
        case "com.apple.Terminal": self = .appleTerminal
        case "com.googlecode.iterm2": self = .iTerm2
        case "com.mitchellh.ghostty": self = .ghostty
        case "dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview": self = .warp
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders": self = .vsCode
        case "com.todesktop.230313mzl4w4u92": self = .cursor
        case "com.anthropic.claudefordesktop": self = .claudeDesktop
        default: return nil
        }
    }

    /// Terminal and iTerm2 can select the exact tab by tty via AppleScript; the others
    /// get app-level activation only.
    public var selectsTabByTTY: Bool { self == .appleTerminal || self == .iTerm2 }
}
