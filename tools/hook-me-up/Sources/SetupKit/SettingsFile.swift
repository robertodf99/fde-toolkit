import Foundation
import HookMeUpCore

/// Reading and writing a Claude Code settings file safely.
public enum SettingsFile {
    /// The settings document; a missing file is `{}`. Invalid JSON or anything other
    /// than an object is refused (nothing will be written).
    static func load(_ url: URL) throws -> JSONValue {
        try read(url).value
    }

    /// Like `load`, keeping the exact bytes for the as-is diff and the "changed since
    /// read" check. Numbers beyond ±2^53 are refused (they would be rewritten wrong).
    public static func read(_ url: URL) throws -> SettingsDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SettingsDocument(original: nil, value: .object([:]))
        }
        let data = try Data(contentsOf: url)
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SettingsFileError.invalidJSON(url.path)
        }
        guard value.objectValue != nil else { throw SettingsFileError.notAnObject(url.path) }
        if let unsafe = JSONText.numberLiterals(String(decoding: data, as: UTF8.self)).first(
            where: JSONText.isUnsafeNumber)
        {
            throw SettingsFileError.unsafeNumber(unsafe)
        }
        return SettingsDocument(original: data, value: value)
    }

    /// What writing `value` changes in the file besides the content itself (the file is
    /// always written sorted, with 2-space indentation). Empty when nothing else changes.
    public static func formattingNotes(original: Data, value: JSONValue) -> [String] {
        let text = String(decoding: original, as: UTF8.self)
        guard text != String(decoding: render(value), as: UTF8.self) else { return [] }
        var notes: [String] = []
        if let keys = JSONText.topLevelKeys(text), keys != keys.sorted() {
            notes.append(
                "key order: \(keys.joined(separator: ", ")) becomes \(keys.sorted().joined(separator: ", ")) (nested objects are sorted too)"
            )
        }
        if text.contains("\": ") {
            notes.append("spacing: \"key\": value becomes \"key\" : value")
        }
        let indented = text.components(separatedBy: "\n").first { $0.first == " " || $0.first == "\t" }
        if let line = indented {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            if indent.contains("\t") || indent.count != 2 {
                notes.append(
                    "indentation: \(indent.contains("\t") ? "tabs" : "\(indent.count) spaces") become 2 spaces")
            }
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).contains("\n") {
            notes.append("indentation: the one-line file becomes one key per line, 2 spaces")
        }
        if !text.hasSuffix("\n") { notes.append("a final newline is added") }
        if text.contains("\\/") { notes.append("escaped slashes (\\/) are written as /") }
        if notes.isEmpty { notes.append("whitespace or nested key order") }
        return notes
    }

    /// Stable output: sorted keys, 2-space indent, final newline.
    public static func render(_ value: JSONValue) -> Data {
        Data((value.pretty() + "\n").utf8)
    }

    /// Copies the current file to `<name>.bak-<timestamp>` first, then writes `value`
    /// atomically (temp file in the same folder, then rename) with the original's
    /// permissions. A symlink is written through to its target. On any failure the
    /// original is left as it was. Returns the backup, or nil when there was no file.
    /// With `ifUnchangedFrom`, the file is re-read first and nothing is written when it
    /// changed since that read (e.g. Claude Code saved it meanwhile).
    @discardableResult
    public static func write(
        _ value: JSONValue, to url: URL, now: Date,
        ifUnchangedFrom document: SettingsDocument? = nil
    ) throws -> URL? {
        let fileManager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        if let document, fileManager.contents(atPath: target.path) != document.original {
            throw SettingsFileError.changedSinceRead(url.path)
        }
        let directory = target.deletingLastPathComponent()
        var mode: mode_t = 0o600
        var backup: URL?

        if fileManager.fileExists(atPath: target.path) {
            var info = stat()
            if stat(target.path, &info) == 0 { mode = info.st_mode & 0o777 }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let base = target.lastPathComponent + ".bak-" + formatter.string(from: now)
            var candidate = directory.appendingPathComponent(base)
            var counter = 1
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = directory.appendingPathComponent("\(base)-\(counter)")
                counter += 1
            }
            try fileManager.copyItem(at: target, to: candidate)
            backup = candidate
        }

        let temp = directory.appendingPathComponent(".\(target.lastPathComponent).tmp-\(getpid())")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        guard fd >= 0 else { throw SettingsFileError.writeFailed("\(temp.path): \(String(cString: strerror(errno)))") }
        let data = render(value)
        var ok = fchmod(fd, mode) == 0
        if ok {
            ok = data.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return raw.isEmpty }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(fd, base + offset, raw.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += written
                }
                return true
            }
        }
        ok = ok && fsync(fd) == 0
        close(fd)
        guard ok, rename(temp.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            unlink(temp.path)
            throw SettingsFileError.writeFailed("\(target.path): \(reason)")
        }
        return backup
    }
}
