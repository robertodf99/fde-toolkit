import Foundation
import Testing

@testable import HookMeUpCore

/// A file system with only the folders and files it is given.
private struct FakeFileSystem: FileSystem {
    var folders: Set<String> = []
    var files: Set<String> = []

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let folder = folders.contains(path)
        isDirectory?.pointee = ObjCBool(folder)
        return folder || files.contains(path)
    }

    func contents(atPath path: String) -> Data? { nil }
}

private let disk = FakeFileSystem(
    folders: ["/home/dev/projects/acme-api", "/home/dev/projects/acme-web"], files: ["/home/dev/notes.txt"])

private func plan(_ bundleID: String?, tty: String? = nil, folder: String? = nil) -> SessionActivation {
    SessionActivation.plan(ownerBundleID: bundleID, tty: tty, folder: folder, fileSystem: disk)
}

@Suite struct SessionActivationTests {
    @Test func terminalAndITermSelectTheTab() {
        #expect(plan("com.apple.Terminal", tty: "ttys003") == .selectTab(.appleTerminal, tty: "ttys003"))
        #expect(plan("com.googlecode.iterm2", tty: "/dev/ttys012") == .selectTab(.iTerm2, tty: "/dev/ttys012"))
        // Without a usable tty they are just brought forward.
        #expect(plan("com.apple.Terminal") == .activateApp)
        #expect(plan("com.apple.Terminal", tty: "not a tty") == .activateApp)
    }

    @Test(arguments: [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.Zed",
    ])
    func editorsOpenTheSessionsFolder(_ bundleID: String) {
        #expect(
            plan(bundleID, tty: "ttys003", folder: "/home/dev/projects/acme-api")
                == .openFolder("/home/dev/projects/acme-api"))
    }

    @Test func theFolderIsNormalised() {
        #expect(
            plan("com.microsoft.VSCode", folder: "/home/dev/projects/acme-web/../acme-api/")
                == .openFolder("/home/dev/projects/acme-api"))
    }

    /// Only an existing absolute folder is opened; otherwise the editor is just brought forward.
    @Test(arguments: [nil, "", "projects/acme-api", "/home/dev/projects/missing", "/home/dev/notes.txt"])
    func editorsWithoutAUsableFolderAreBroughtForward(_ folder: String?) {
        #expect(plan("com.microsoft.VSCode", folder: folder) == .activateApp)
    }

    @Test(arguments: [
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.anthropic.claudefordesktop", "org.example.app",
    ])
    func otherAppsAreBroughtForward(_ bundleID: String) {
        #expect(plan(bundleID, tty: "ttys003", folder: "/home/dev/projects/acme-api") == .activateApp)
    }

    @Test func noAppNoActivation() {
        #expect(plan(nil, tty: "ttys003", folder: "/home/dev/projects/acme-api") == .none)
    }
}
