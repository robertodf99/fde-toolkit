import Foundation

/// Read-only file access, injected so HookMeUpCore does no I/O of its own. The method
/// names match `FileManager`, so a conformance is a thin wrapper around it.
public protocol FileSystem {
    /// Whether an item exists at `path`; when it does, `isDirectory` tells whether it is a folder.
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    /// The file's bytes, or nil when it cannot be read.
    func contents(atPath path: String) -> Data?
}
