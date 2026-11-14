import Foundation
import Testing

@testable import SetupKit

private let keg = "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app"
private let opt = "/opt/homebrew/opt/hook-me-up/Hook Me Up.app"

/// `canonicalPath` for a made-up Homebrew prefix: bin and opt are links into the keg.
private func resolve(_ path: String) -> String {
    path
        .replacingOccurrences(
            of: "/opt/homebrew/bin/hook-me-up-setup", with: keg + "/Contents/MacOS/hook-me-up-setup"
        )
        .replacingOccurrences(of: "/opt/homebrew/opt/hook-me-up/", with: "/opt/homebrew/Cellar/hook-me-up/0.2.0/")
}

@Suite struct AppLocationTests {
    @Test func theAppAroundAnExecutable() {
        #expect(AppLocation.appContaining("/A/Hook Me Up.app/Contents/MacOS/hook-me-up-setup") == "/A/Hook Me Up.app")
        #expect(AppLocation.appContaining("/repo/.build/release/hook-me-up-setup") == nil)
        #expect(AppLocation.appContaining("/A/Folder/Contents/MacOS/x") == nil)
    }

    @Test func homebrewsOptPathForAKeg() {
        #expect(
            AppLocation.homebrewOptPath(for: keg + "/Contents/MacOS/hook-me-up") == opt + "/Contents/MacOS/hook-me-up")
        #expect(AppLocation.homebrewOptPath(for: keg) == opt)
        #expect(AppLocation.homebrewOptPath(for: "/Users/me/Applications/Hook Me Up.app") == nil)
        #expect(AppLocation.homebrewOptPath(for: "/opt/homebrew/Cellar/hook-me-up/0.2.0") == nil)
    }

    @Test func theDefaultHookIsTheOneNextToThisProgram() {
        let everything: (String) -> Bool = { _ in true }
        let fallback = "/Users/me/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        // Homebrew: run through the bin link, the keg resolves to the stable opt path.
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: "/opt/homebrew/bin/hook-me-up-setup", canonicalPath: resolve, isExecutable: everything,
                fallback: fallback) == opt + "/Contents/MacOS/hook-me-up")
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
        // A keg whose opt link is missing (or points elsewhere): the keg's own hook.
        #expect(
            AppLocation.defaultHookPath(
                setupExecutable: keg + "/Contents/MacOS/hook-me-up-setup", canonicalPath: { $0 },
                isExecutable: everything, fallback: fallback) == keg + "/Contents/MacOS/hook-me-up")
    }

    @Test func realSymlinksResolve() throws {
        let tree = try TempTree()
        try tree.file("Cellar/hook-me-up/1.0/Hook Me Up.app/Contents/MacOS/hook-me-up", "#!/bin/sh\n")
        try FileManager.default.createDirectory(atPath: tree.path("opt"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: tree.path("opt/hook-me-up"), withDestinationPath: tree.path("Cellar/hook-me-up/1.0"))
        let viaLink = tree.path("opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up")
        #expect(
            AppLocation.resolvingSymlinks(viaLink)
                == AppLocation.resolvingSymlinks(
                    tree.path("Cellar/hook-me-up/1.0/Hook Me Up.app/Contents/MacOS/hook-me-up")))
    }
}
