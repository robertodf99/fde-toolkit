import Foundation
import Testing

@testable import SetupKit

@Suite struct AppLocationTests {
    @Test func theAppAroundAnExecutable() {
        #expect(AppLocation.appContaining("/A/Hook Me Up.app/Contents/MacOS/hook-me-up-setup") == "/A/Hook Me Up.app")
        #expect(AppLocation.appContaining("/repo/.build/release/hook-me-up-setup") == nil)
        #expect(AppLocation.appContaining("/A/Folder/Contents/MacOS/x") == nil)
    }

    @Test func theDefaultHookIsTheOneNextToThisProgram() {
        let everything: (String) -> Bool = { _ in true }
        let fallback = "/Users/me/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        // Run through a link: the hook next to the program it links to.
        let link = "/Users/me/bin/hook-me-up-setup"
        let linked = "/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup"
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: link, canonicalPath: { $0 == link ? linked : $0 }, isExecutable: everything,
                fallback: fallback) == "/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up")
        // The installer's copy.
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: "/Users/me/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup",
                canonicalPath: { $0 }, isExecutable: everything, fallback: "/elsewhere") == fallback)
        // A build folder, or an app without its hook: the installer's location.
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: "/repo/.build/release/hook-me-up-setup", canonicalPath: { $0 },
                isExecutable: everything, fallback: fallback) == fallback)
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: "/X/HookMeUp.app/Contents/MacOS/hook-me-up-setup", canonicalPath: { $0 },
                isExecutable: { _ in false }, fallback: fallback) == fallback)
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: nil, canonicalPath: { $0 }, isExecutable: everything, fallback: fallback) == fallback)
    }

    @Test func realSymlinksResolve() throws {
        let tree = try TempTree()
        try tree.file("real/Hook Me Up.app/Contents/MacOS/hook-me-up", "#!/bin/sh\n")
        try FileManager.default.createSymbolicLink(atPath: tree.path("link"), withDestinationPath: tree.path("real"))
        let viaLink = tree.path("link/Hook Me Up.app/Contents/MacOS/hook-me-up")
        #expect(
            AppLocation.resolvingSymlinks(viaLink)
                == AppLocation.resolvingSymlinks(tree.path("real/Hook Me Up.app/Contents/MacOS/hook-me-up")))
    }
}
