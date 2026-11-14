import Foundation
import HookMeUpCore

/// The real file system, for `ProjectInfo.resolve` in the hook.
struct LocalFileSystem: FileSystem {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }
}
