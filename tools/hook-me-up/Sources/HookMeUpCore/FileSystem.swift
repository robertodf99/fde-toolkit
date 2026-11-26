import Foundation

/// Read-only file access, injected so HookMeUpCore does no I/O of its own. The method
/// names match `FileManager`, so a conformance is a thin wrapper around it.
public protocol FileSystem {
    /// Whether an item exists at `path`; when it does, `isDirectory` tells whether it is a folder.
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    /// The file's bytes, or nil when it cannot be read.
    func contents(atPath path: String) -> Data?
    /// The file's bytes when it is a regular file of at most `limit` bytes; nil otherwise.
    /// A conformance that can should check the size before reading (the default reads first).
    func contents(atPath path: String, limit: Int) -> Data?
}

extension FileSystem {
    /// Reads the whole file, then drops it when it is over `limit` bytes.
    public func contents(atPath path: String, limit: Int) -> Data? {
        guard let data = contents(atPath: path), data.count <= limit else { return nil }
        return data
    }
}
