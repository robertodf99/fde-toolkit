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

/// A generator that hands out the values it is given, for reproducible tokens.
private struct FixedRandom: RandomNumberGenerator {
    var values: [UInt64]

    mutating func next() -> UInt64 { values.isEmpty ? 0 : values.removeFirst() }
}

private let osc2: [UInt8] = [0x1B, 0x5D, 0x32, 0x3B]  // ESC ] 2 ;
private let bel: UInt8 = 0x07

/// Several terminals in the session's folder: a marker title written to the session's tty
/// tells which one runs it.
@Suite struct GhosttyTitleMarkerTests {
    @Test func theTitlesAreReadOneTerminalPerLine() {
        let output = list([
            "\(idA)\t✳ Claude Code", "\(idB)\t", "\(idC)\tvim\tnotes.txt", "not-an-id!\tx", "no tab here",
            "\(idA)\tlisted again",
        ])
        #expect(
            GhosttyTerminals.terminalTitles(fromList: output) == [idA: "✳ Claude Code", idB: "", idC: "vim\tnotes.txt"])
        #expect(GhosttyTerminals.terminalTitles(fromList: "").isEmpty)
    }

    /// The titles script is fixed text that leaves out a title with a line break (so every
    /// line is one terminal) and takes no arguments.
    @Test func theTitlesScriptIsFixed() {
        let titles = GhosttyTerminals.titles
        #expect(titles.arguments.isEmpty)
        #expect(titles.source.contains("on run argv"))
        #expect(titles.source.contains("character id 10") && titles.source.contains("character id 13"))
    }

    @Test func theMarkerOutputIsReadAsIDs() {
        #expect(GhosttyTerminals.ids(fromOutput: list([idA])) == [idA])
        #expect(GhosttyTerminals.ids(fromOutput: list([idA, "not an id!", idB, idA])) == [idA, idB])
        #expect(GhosttyTerminals.ids(fromOutput: "").isEmpty)
        #expect(GhosttyTerminals.ids(fromOutput: "\n\n").isEmpty)
    }

    /// Only one terminal shows the marker, and it is one of the folder's terminals.
    @Test func theMarkedTerminalIsTheOneInTheFolderThatShowsTheMarker() {
        let candidates = [idA, idB]
        #expect(GhosttyTerminals.marked(ids: [idA], candidates: candidates) == idA)
        #expect(GhosttyTerminals.marked(ids: [idB, idB], candidates: candidates) == idB)
        #expect(GhosttyTerminals.marked(ids: [], candidates: candidates) == nil)
        #expect(GhosttyTerminals.marked(ids: [idA, idB], candidates: candidates) == nil)
        #expect(GhosttyTerminals.marked(ids: [idC], candidates: candidates) == nil)
        #expect(GhosttyTerminals.marked(ids: [idA], candidates: []) == nil)
    }

    /// The candidates are the terminals `match` counts: in the folder, each once.
    @Test func theCandidatesAreTheTerminalsInTheFolder() {
        let all = terminals([
            (idA, "/Users/dev/projects/acme-api"), (idB, "/Users/dev/projects/acme-api/"), (idC, "/Users/dev"),
            (idA, "/Users/dev/projects/acme-api"),
        ])
        #expect(GhosttyTerminals.candidates(folder: "/Users/dev/projects/acme-api", in: all) == [idA, idB])
        #expect(GhosttyTerminals.candidates(folder: "/Users/dev/scratch", in: all).isEmpty)
        #expect(GhosttyTerminals.candidates(folder: "relative", in: all).isEmpty)
    }

    @Test func tokensAreHMUAndSixteenHexDigits() {
        var fixed = FixedRandom(values: [0x0123_4567_89AB_CDEF, 0])
        #expect(GhosttyTerminals.makeToken(using: &fixed) == "hmu-0123456789abcdef")
        #expect(GhosttyTerminals.makeToken(using: &fixed) == "hmu-0000000000000000")
        var system = SystemRandomNumberGenerator()
        let first = GhosttyTerminals.makeToken(using: &system)
        let second = GhosttyTerminals.makeToken(using: &system)
        #expect(GhosttyTerminals.isValidToken(first) && GhosttyTerminals.isValidToken(second))
        #expect(first != second)
    }

    @Test(arguments: [
        "", "hmu-", "hmu-0123456789abcde", "hmu-0123456789abcdef0", "hmu-0123456789ABCDEF", "xyz-0123456789abcdef",
        "hmu-0123456789abcdeg", "hmu-01234567\"9abcdef", " hmu-0123456789abcdef", "hmu-0123456789abcdef\n",
        "hmu-０123456789abcdef",
    ])
    func onlyWellFormedTokensAreValid(_ token: String) {
        #expect(!GhosttyTerminals.isValidToken(token))
    }

    /// OSC 2 (set the window title), ended by BEL, byte for byte.
    @Test func theTitleSequenceIsOSC2EndedByBEL() {
        #expect(
            GhosttyTerminals.titleSequence("hmu-0123456789abcdef") == osc2 + Array("hmu-0123456789abcdef".utf8) + [bel])
        #expect(GhosttyTerminals.titleSequence("") == osc2 + [bel])
        #expect(GhosttyTerminals.titleSequence("✳ café") == osc2 + Array("✳ café".utf8) + [bel])
        #expect(
            GhosttyTerminals.titleSequence("✳ café") == osc2 + [0xE2, 0x9C, 0xB3, 0x20, 0x63, 0x61, 0x66, 0xC3, 0xA9]
                + [bel])
    }

    /// A title can never end the sequence early or start another one.
    @Test func theTitleSequenceCarriesNoControlCharacters() {
        let sequence = GhosttyTerminals.titleSequence("a\u{1B}]2;evil\u{07}b\u{9C}c\u{0A}d")
        #expect(sequence == osc2 + Array("a]2;evilbcd".utf8) + [bel])
        let inner = sequence.dropFirst(osc2.count).dropLast()
        #expect(!inner.contains { $0 < 0x20 || $0 == 0x7F })
    }

    @Test func titlesLoseC0DELAndC1ControlCharacters() {
        let controls =
            (0x00...0x1F).map { String(UnicodeScalar(UInt8($0))) } + ["\u{7F}"]
            + (0x80...0x9F).map { String(Character(UnicodeScalar($0)!)) }
        #expect(GhosttyTerminals.sanitizedTitle("x" + controls.joined() + "y") == "xy")
        #expect(GhosttyTerminals.sanitizedTitle("✳ Claude Code — café ¡olé!") == "✳ Claude Code — café ¡olé!")
        #expect(GhosttyTerminals.sanitizedTitle("tab\there") == "tabhere")
        #expect(GhosttyTerminals.sanitizedTitle("") == "")
    }

    /// At most 255 bytes of UTF-8, cut between scalars.
    @Test func longTitlesAreCutAt255BytesBetweenScalars() {
        let exact = String(repeating: "a", count: 255)
        #expect(GhosttyTerminals.sanitizedTitle(exact) == exact)
        #expect(GhosttyTerminals.sanitizedTitle(exact + "b") == exact)
        let accents = String(repeating: "é", count: 200)  // 2 bytes each
        #expect(GhosttyTerminals.sanitizedTitle(accents) == String(repeating: "é", count: 127))
        let emoji = "a" + String(repeating: "😀", count: 100)  // 4 bytes each
        #expect(GhosttyTerminals.sanitizedTitle(emoji) == "a" + String(repeating: "😀", count: 63))
        let mixed = String(repeating: "ab✳", count: 80)  // 5 bytes per group
        let cut = GhosttyTerminals.sanitizedTitle(mixed)
        #expect(cut.utf8.count <= 255 && cut.utf8.count >= 252)
        #expect(mixed.hasPrefix(cut))
        // Control characters are dropped before the cut, so they don't use up the room.
        #expect(GhosttyTerminals.sanitizedTitle(String(repeating: "\u{07}", count: 300) + "ok") == "ok")
    }

    @Test(arguments: [
        ("ttys003", "/dev/ttys003"), ("/dev/ttys012", "/dev/ttys012"), ("ttys000", "/dev/ttys000"),
        ("ttys1023", "/dev/ttys1023"), ("/dev/ttys9999", "/dev/ttys9999"),
    ])
    func plainPseudoTerminalsHaveADevicePath(_ tty: String, _ path: String) {
        #expect(GhosttyTerminals.ttyDevicePath(tty) == path)
    }

    @Test(arguments: [
        "", "ttys0", "ttys00", "/dev/ttys0", "ttys12345", "tty", "/dev/tty", "console", "/dev/console", "ttyp0",
        "pty003", "/dev/ptys003", "ptmx", "/dev/../dev/ttys003", "../ttys003", "/dev/ttys003/", "/dev//ttys003",
        " ttys003", "ttys003 ", "ttys003\n", "ttys00\"3", "ttys٠٠٣", "ttys００３", "/private/dev/ttys003", "dev/ttys003",
        "TTYS003", "/dev/TTYS003", "ttys-03", "ttys+003", "ttys0x3",
    ])
    func anythingElseHasNone(_ tty: String) {
        #expect(GhosttyTerminals.ttyDevicePath(tty) == nil)
    }

    @Test func noTTYHasNoDevicePath() {
        #expect(GhosttyTerminals.ttyDevicePath(nil) == nil)
    }

    /// The scripts are fixed text: the token goes to the find script as an argument, and
    /// neither it nor a tty is ever part of a script.
    @Test func theTokenAndTheTTYNeverGoIntoAScript() throws {
        let token = "hmu-0123456789abcdef"
        let find = try #require(GhosttyTerminals.findMarker(token: token))
        #expect(find.arguments == [token])
        #expect(!find.source.contains(token))
        #expect(find.source.contains("on run argv"))
        #expect(GhosttyTerminals.findMarker(token: "hmu-fedcba9876543210")?.source == find.source)
        #expect(GhosttyTerminals.findMarker(token: "\" & (do shell script \"touch /tmp/x\") & \"") == nil)
        #expect(GhosttyTerminals.findMarker(token: "") == nil)
        for command in [GhosttyTerminals.titles, GhosttyTerminals.list, GhosttyTerminals.activate, find] {
            #expect(!command.source.contains("ttys"))
            #expect(!command.source.contains("hmu-"))
        }
    }

    /// The find script waits for Ghostty to show the title: it looks up to ten times, a
    /// tenth of a second apart, outside the tell block.
    @Test func theFindScriptRetries() throws {
        let find = try #require(GhosttyTerminals.findMarker(token: "hmu-0123456789abcdef"))
        #expect(find.source.contains("repeat 10 times"))
        #expect(find.source.contains("delay 0.1"))
    }
}
