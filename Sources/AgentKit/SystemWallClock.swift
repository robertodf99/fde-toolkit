import Foundation

/// The system clock.
public struct SystemWallClock: WallClock {
    /// Creates the system clock.
    public init() {}

    /// The current date.
    public var now: Date { Date() }
}
