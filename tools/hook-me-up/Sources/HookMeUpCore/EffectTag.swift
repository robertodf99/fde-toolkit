import Foundation

/// A rule-based warning about a request, shown as text in the notification.
public enum EffectTag: String, Codable, Sendable {
    /// Talks to the network.
    case network
    /// Deletes files.
    case deletesFiles
    /// Pushes to a git remote.
    case gitPush
    /// Writes outside the project folder.
    case writesOutsideProject
}

extension EffectTag {
    /// Plain-language label, as shown in a notification ("⚠︎ Leaves your machine").
    var label: String {
        switch self {
        case .network: "Leaves your machine"
        case .deletesFiles: "Deletes files"
        case .gitPush: "Pushes to a remote"
        case .writesOutsideProject: "Writes outside the project"
        }
    }
}

extension EffectTag {
    /// Tags in a stable display order.
    static func ordered(_ tags: Set<EffectTag>) -> [EffectTag] {
        [.network, .deletesFiles, .gitPush, .writesOutsideProject].filter(tags.contains)
    }
}
