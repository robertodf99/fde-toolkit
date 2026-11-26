import Foundation
import HookMeUpCore
import Testing

@testable import SetupKit

@Suite struct SettingsFileTests {
    @Test func backupCreatedBeforeWrite() throws {
        let tree = try TempTree()
        let url = URL(fileURLWithPath: tree.path("settings.json"))
        try tree.file("settings.json", #"{"model":"opus"}"#)
        chmod(url.path, 0o600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let backup = try #require(try SettingsFile.write(.object(["model": "sonnet"]), to: url, now: now))
        #expect(backup.lastPathComponent.hasPrefix("settings.json.bak-"))
        #expect(try String(contentsOf: backup, encoding: .utf8) == #"{"model":"opus"}"#)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\n  \"model\" : \"sonnet\"\n}\n")
        var info = stat()
        #expect(stat(url.path, &info) == 0 && info.st_mode & 0o777 == 0o600)  // permissions kept
    }

    @Test func writeToMissingFileCreatesItWithoutBackup() throws {
        let tree = try TempTree()
        let url = URL(fileURLWithPath: tree.path("new/settings.json"))
        try tree.dir("new")
        #expect(try SettingsFile.write(.object([:]), to: url, now: Date()) == nil)
        #expect(try SettingsFile.load(url) == .object([:]))
    }

    @Test func atomicWriteLeavesOriginalOnFailure() throws {
        let tree = try TempTree()
        let dir = try tree.dir("locked")
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"keep":true}"#.utf8).write(to: url)
        chmod(dir.path, 0o500)  // nothing new can be created next to it
        defer { chmod(dir.path, 0o700) }
        #expect(throws: (any Error).self) {
            try SettingsFile.write(.object(["keep": .bool(false)]), to: url, now: Date())
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == #"{"keep":true}"#)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
    }

    @Test func writeGoesThroughASymlink() throws {
        let tree = try TempTree()
        try tree.file("dotfiles/settings.json", "{}")
        let link = URL(fileURLWithPath: tree.path("settings.json"))
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: tree.path("dotfiles/settings.json"))
        _ = try SettingsFile.write(.object(["a": "b"]), to: link, now: Date())
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == tree.path("dotfiles/settings.json"))
        #expect(try SettingsFile.load(URL(fileURLWithPath: tree.path("dotfiles/settings.json"))) == .object(["a": "b"]))
    }

    @Test func renderIsStableSortedTwoSpace() throws {
        let value: JSONValue = .object(["b": .number(1), "a": .object(["d": .bool(true), "c": "x/y"])])
        #expect(
            String(decoding: SettingsFile.render(value), as: UTF8.self) == """
                {
                  "a" : {
                    "c" : "x/y",
                    "d" : true
                  },
                  "b" : 1
                }

                """)
    }
}

/// the installer shows the real text changes, refuses lossy numbers, and never
/// overwrites edits made after it read the file.
@Suite struct SettingsInstallerSafetyTests {
    @Test func diffIsAgainstTheFileTextAsIs() throws {
        let original = #"{"model":"opus"}"#
        let new = String(decoding: SettingsFile.render(.object(["model": "opus"])), as: UTF8.self)
        let diff = SettingsMerger.diff(oldText: original, newText: new)
        #expect(diff.contains(#"- {"model":"opus"}"#))
        #expect(diff.contains(#"+   "model" : "opus""#))
        #expect(SettingsMerger.diff(oldText: new, newText: new) == "")
    }

    @Test func formattingNotesListKeyOrderAndSpacing() throws {
        let messy = Data("{\n    \"model\": \"opus\",\n    \"env\": {\"A\": \"x\\/y\"}\n}".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: messy)
        let notes = SettingsFile.formattingNotes(original: messy, value: value)
        #expect(notes.contains { $0.contains("key order") && $0.contains("model, env") })
        #expect(notes.contains { $0.contains("spacing") })
        #expect(notes.contains { $0.contains("indentation") })
        #expect(notes.contains { $0.contains("final newline") })
        #expect(notes.contains { $0.contains("slash") })
        // A file already in the written format has nothing to report.
        let clean = SettingsFile.render(value)
        #expect(SettingsFile.formattingNotes(original: clean, value: value).isEmpty)
    }

    @Test func integersBeyond2to53AreRefused() throws {
        let tree = try TempTree()
        for big in ["9007199254740993", "-9007199254740993", "12345678901234567890", "1e300"] {
            try tree.file("big.json", #"{"n": \#(big)}"#)
            #expect(throws: SettingsFileError.self, "\(big)") {
                try SettingsFile.load(URL(fileURLWithPath: tree.path("big.json")))
            }
        }
        try tree.file("ok.json", #"{"n": 9007199254740992, "m": -3, "f": 0.5, "s": "99999999999999999999"}"#)
        #expect(
            try SettingsFile.load(URL(fileURLWithPath: tree.path("ok.json")))["n"] == .number(9_007_199_254_740_992))
    }

    @Test func refusesToWriteWhenTheFileChangedSinceItWasRead() throws {
        let tree = try TempTree()
        let url = URL(fileURLWithPath: tree.path("settings.json"))
        try tree.file("settings.json", #"{"model":"opus"}"#)
        let document = try SettingsFile.read(url)
        try tree.file("settings.json", #"{"model":"sonnet"}"#)  // edited meanwhile (e.g. by Claude Code)
        #expect(throws: SettingsFileError.changedSinceRead(url.path)) {
            try SettingsFile.write(.object([:]), to: url, now: Date(), ifUnchangedFrom: document)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == #"{"model":"sonnet"}"#)
        // Unchanged: the write goes ahead.
        let fresh = try SettingsFile.read(url)
        _ = try SettingsFile.write(.object([:]), to: url, now: Date(), ifUnchangedFrom: fresh)
        #expect(try SettingsFile.load(url) == .object([:]))
        // A file that appears after reading "missing" is not overwritten either.
        let missingURL = URL(fileURLWithPath: tree.path("later.json"))
        let missing = try SettingsFile.read(missingURL)
        try tree.file("later.json", "{}")
        #expect(throws: SettingsFileError.self) {
            try SettingsFile.write(.object(["a": "b"]), to: missingURL, now: Date(), ifUnchangedFrom: missing)
        }
    }

    @Test func tempFileFailureLeavesOriginal() throws {
        let tree = try TempTree()
        let url = URL(fileURLWithPath: tree.path("settings.json"))
        try tree.file("settings.json", #"{"keep":true}"#)
        try tree.file(".settings.json.tmp-\(getpid())", "squatter")  // O_EXCL create fails
        #expect(throws: SettingsFileError.self) { try SettingsFile.write(.object([:]), to: url, now: Date()) }
        #expect(try String(contentsOf: url, encoding: .utf8) == #"{"keep":true}"#)
        #expect(
            try String(contentsOf: URL(fileURLWithPath: tree.path(".settings.json.tmp-\(getpid())")), encoding: .utf8)
                == "squatter")
    }

    @Test func renameFailureRemovesTempAndLeavesTarget() throws {
        let tree = try TempTree()
        try tree.file("settings.json/inner", "x")  // the target is a non-empty directory: rename fails
        let url = URL(fileURLWithPath: tree.path("settings.json"))
        #expect(throws: SettingsFileError.self) { try SettingsFile.write(.object([:]), to: url, now: Date()) }
        #expect(try String(contentsOf: URL(fileURLWithPath: tree.path("settings.json/inner")), encoding: .utf8) == "x")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tree.root.path).filter {
            $0.contains(".tmp-")
        }
        #expect(leftovers.isEmpty)
    }
}
