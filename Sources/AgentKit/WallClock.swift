import Foundation

/// The current date, injectable for tests. Named `WallClock` so it does not shadow the
/// standard library's `Clock` protocol.
public protocol WallClock: Sendable {
    /// The current date.
    var now: Date { get }
}
