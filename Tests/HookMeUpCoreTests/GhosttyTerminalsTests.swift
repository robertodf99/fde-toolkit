import Foundation
import Testing

@testable import HookMeUpCore

private let idA = "4F9C2E1A-8B7D-4C3E-9A0B-1D2E3F405162"
private let idB = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
private let idC = "C0FFEE00-0000-4000-8000-000000000001"

private func list(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

private func terminals(_ pairs: [(String, String)]) -> [GhosttyTerminals.Terminal] {
    pairs.map { GhosttyTerminals.Terminal(id: $0.0, workingDirectory: $0.1) }
}

@Suite struct GhosttyTerminalsTests {
    @Test func theListIsReadOneTerminalPerLine() {
        let output = list([
            "\(idA)\t/Users/dev/projects/acme-api", "\(idB)\t/Users/dev/My Projects/with\ttab",
            "\(idC)\t/tmp/",
        ])
        #expect(
            GhosttyTerminals.terminals(fromList: output)
                == terminals([
                    (idA, "/Users/dev/projects/acme-api"), (idB, "/Users/dev/My Projects/with\ttab"), (idC, "/tmp/"),
                ]))
        #expect(GhosttyTerminals.terminals(fromList: "").isEmpty)
    }

    /// Lines without a tab, with an id that isn't plain, or with a folder that isn't
    /// absolute are skipped; the others still count.
    @Test func malformedLinesAndInvalidIDsAreSkipped() {
        let output = list([
            "no tab here", "\t/Users/dev/projects/acme-api", "not-an-id!\t/Users/dev/projects/acme-api",
            "\"; do shell script \"x\"\t/Users/dev", "\(idA)\tprojects/acme-api", "\(idB)\t", "",
            "\(idC)\t/Users/dev/projects/acme-api",
        ])
        #expect(GhosttyTerminals.terminals(fromList: output) == terminals([(idC, "/Users/dev/projects/acme-api")]))
    }

    @Test func idsAreUUIDLike() {
        #expect(GhosttyTerminals.isValidID(idA))
        #expect(GhosttyTerminals.isValidID(idB))
        #expect(GhosttyTerminals.isValidID("abc-123"))
        for bad in [
            "", "4F9C 2E1A", "4F9C\"2E1A", "id\"; do shell script \"rm\"", "g123", "4F9C\n2E1A", "１２３",
            String(repeating: "a", count: 65),
        ] {
            #expect(!GhosttyTerminals.isValidID(bad), "\(bad)")
        }
    }

    @Test func exactlyOneTerminalInTheFolderMatches() {
        let all = terminals([
            (idA, "/Users/dev/projects/acme-api"), (idB, "/Users/dev/projects/acme-web"), (idC, "/Users/dev"),
        ])
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects/acme-api", in: all) == .unique(id: idA))
        // A terminal in a subfolder or a parent folder is not the session's.
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects", in: all) == .none)
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects/acme-api/src", in: all) == .none)
        #expect(GhosttyTerminals.match(folder: "/Users/dev/scratch", in: []) == .none)
    }

    /// Two terminals in the session's folder (a split for git, say): which one runs the
    /// session can't be told, so none is focused.
    @Test func severalTerminalsInTheFolderAreNotAMatch() {
        let all = terminals([
            (idA, "/Users/dev/projects/acme-api"), (idB, "/Users/dev/projects/acme-api/"), (idC, "/Users/dev"),
        ])
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects/acme-api", in: all) == .several(2))
        // The same terminal listed twice counts once.
        let twice = terminals([(idA, "/Users/dev/projects/acme-api"), (idA, "/Users/dev/projects/acme-api")])
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects/acme-api", in: twice) == .unique(id: idA))
    }

    @Test func pathsAreComparedNormalised() {
        let all = terminals([(idA, "/private/tmp/scratch/"), (idB, "/Users/dev/projects/./acme-web/../acme-api")])
        #expect(GhosttyTerminals.match(folder: "/tmp/scratch", in: all) == .unique(id: idA))
        #expect(GhosttyTerminals.match(folder: "/tmp/scratch/", in: all) == .unique(id: idA))
        #expect(GhosttyTerminals.match(folder: "/Users/dev/projects/acme-api", in: all) == .unique(id: idB))
    }

    /// Symbolic links are resolved on both sides (`resolve` stands in for the file system).
    @Test func symbolicLinksAreResolved() {
        let resolve: (String) -> String = { path in
            path.hasPrefix("/Users/dev/link") ? "/Volumes/work" + path.dropFirst("/Users/dev/link".count) : path
        }
        let all = terminals([(idA, "/Volumes/work/acme-api"), (idB, "/Users/dev/projects/acme-web")])
        #expect(
            GhosttyTerminals.match(folder: "/Users/dev/link/acme-api", in: all, resolve: resolve) == .unique(id: idA))
        #expect(GhosttyTerminals.match(folder: "/Users/dev/link/acme-api", in: all) == .none)
    }

    @Test func aFolderThatIsNotAbsoluteMatchesNothing() {
        let all = terminals([(idA, "/Users/dev/projects/acme-api")])
        #expect(GhosttyTerminals.match(folder: "Users/dev/projects/acme-api", in: all) == .none)
        #expect(GhosttyTerminals.match(folder: "", in: all) == .none)
    }

    /// The scripts are fixed text: neither the folder nor the id is ever part of one; the
    /// id goes as an argument, and only a plain one.
    @Test func theFolderAndTheIDNeverGoIntoAScript() throws {
        let folder = "/Users/dev/projects/acme-api"
        for command in [GhosttyTerminals.list, GhosttyTerminals.activate] {
            #expect(command.arguments.isEmpty)
            #expect(!command.source.contains(folder))
        }
        let focus = try #require(GhosttyTerminals.focus(id: idA))
        #expect(focus.arguments == [idA])
        #expect(!focus.source.contains(idA))
        #expect(focus.source.contains("on run argv"))
        #expect(GhosttyTerminals.focus(id: idB)?.source == focus.source)
        #expect(GhosttyTerminals.focus(id: "\" & (do shell script \"touch /tmp/x\") & \"") == nil)
        #expect(GhosttyTerminals.focus(id: "") == nil)
    }
}
