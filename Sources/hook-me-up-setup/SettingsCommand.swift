// hook-me-up-setup install|uninstall: adds (or removes) Hook Me Up's hooks in a Claude
// Code settings file, leaving every other key and hook untouched. Always shows the diff
// first; writes only after "y" (or --yes), after a backup, atomically. --dry-run never
// writes.
import DoctorKit
import Foundation
import HookMeUpCore
import SetupKit

func runSettingsCommand(_ command: String, _ arguments: [String]) -> Never {
    var arguments = arguments
    var settingsURL = HookMeUpPaths.claudeSettingsURL
    // Without --hook: the hook next to this program, else where the installer puts it.
    var hookPath = AppLocation.defaultHookPath(
        setupExecutable: Bundle.main.executablePath, canonicalPath: AppLocation.resolvingSymlinks,
        isExecutable: FileManager.default.isExecutableFile(atPath:), fallback: HookMeUpPaths.installedHookPath)
    var timeout = 600
    var statePath = HookMeUpPaths.defaultSocketURL
        .deletingLastPathComponent().appendingPathComponent("setup-state.json").path
    var dryRun = false
    var assumeYes = false
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--dry-run": dryRun = true
        case "--yes": assumeYes = true
        case "--settings", "--hook", "--timeout", "--state":
            guard let value = arguments.first, !value.isEmpty else { fail("\(argument) needs a value\n\(usage)") }
            arguments.removeFirst()
            switch argument {
            case "--settings": settingsURL = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--hook": hookPath = (value as NSString).expandingTildeInPath
            case "--state": statePath = (value as NSString).expandingTildeInPath
            default:
                guard let seconds = Int(value), seconds > 10 else {
                    fail("--timeout must be a number of seconds above 10")
                }
                timeout = seconds
            }
        default:
            fail("unknown argument \(argument)\n\(usage)")
        }
    }
    guard hookPath.hasPrefix("/") else { fail("--hook must be an absolute path") }

    let document: SettingsDocument
    do {
        document = try SettingsFile.read(settingsURL)
    } catch {
        fail("refusing to touch \(settingsURL.path): \(error)")
    }
    let old = document.value
    if command == "install" { warnAboutOtherInstallations(in: old, settingsURL: settingsURL, hookPath: hookPath) }

    // Whether the settings had a `hooks` object before our install: recorded
    // at install, used at uninstall to restore an originally empty `"hooks": {}` exactly.
    let stateKey = settingsURL.resolvingSymlinksInPath().path
    func loadState(_ statePath: String) -> [String: JSONValue] {
        guard let data = FileManager.default.contents(atPath: statePath),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return [:] }
        return value.objectValue ?? [:]
    }
    func saveState(_ state: [String: JSONValue], to statePath: String) {
        let url = URL(fileURLWithPath: statePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? SettingsFile.render(.object(state)).write(to: url, options: .atomic)
    }
    let canonical = AppLocation.resolvingSymlinks
    let hadHooksObject = SettingsMerger.hasHooksObject(
        SettingsMerger.uninstall(from: old, hookPath: hookPath, canonicalPath: canonical))
    let keepEmptyHooks = loadState(statePath)[stateKey]?["hadHooksObject"]?.boolValue ?? false

    let new: JSONValue
    do {
        new =
            command == "install"
            ? try SettingsMerger.install(
                into: old, hookPath: hookPath, permissionTimeout: timeout, canonicalPath: canonical)
            : SettingsMerger.uninstall(
                from: old, hookPath: hookPath, keepEmptyHooks: keepEmptyHooks, canonicalPath: canonical)
    } catch {
        fail("refusing to touch \(settingsURL.path): unexpected settings shape (\(error))")
    }

    guard SettingsMerger.diff(old: old, new: new) != "" else {
        print(
            "No changes: \(settingsURL.path) is already \(command == "install" ? "set up" : "free of Hook Me Up's hooks")."
        )
        exit(0)
    }
    // The text diff is against the file exactly as it is on disk.
    let originalText = document.original.map { String(decoding: $0, as: UTF8.self) } ?? ""
    let newText = String(decoding: SettingsFile.render(new), as: UTF8.self)
    let notes = document.original.map { SettingsFile.formattingNotes(original: $0, value: old) } ?? []
    if !notes.isEmpty {
        print(
            """
            Warning: \(settingsURL.path) will be rewritten with sorted keys and 2-space indentation.
            Outside the hooks, these parts change in form only, not in content:
            \(notes.map { "  - " + $0 }.joined(separator: "\n"))

            Content changes (the hooks):
            \(SettingsMerger.diff(old: old, new: new))

            """)
    }
    print(
        "Exact text changes to \(settingsURL.path), against the file as it is now:\n\(SettingsMerger.diff(oldText: originalText, newText: newText))\n"
    )
    if command == "install", !FileManager.default.isExecutableFile(atPath: hookPath) {
        print("Note: \(hookPath) does not exist yet (make install puts it there).")
    }
    if dryRun {
        print("Dry run: nothing was written.")
        exit(0)
    }
    if !assumeYes {
        print("Write these changes to \(settingsURL.path)? [y/N] ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        guard answer == "y" || answer == "yes" else {
            print("Nothing written.")
            exit(1)
        }
    }
    do {
        let backup = try SettingsFile.write(new, to: settingsURL, now: Date(), ifUnchangedFrom: document)
        var state = loadState(statePath)
        if command == "install" {
            if state[stateKey] == nil { state[stateKey] = .object(["hadHooksObject": .bool(hadHooksObject)]) }
        } else {
            state[stateKey] = nil
        }
        saveState(state, to: statePath)
        print("Wrote \(settingsURL.path)" + (backup.map { " (backup: \($0.path))" } ?? ""))
    } catch SettingsFileError.changedSinceRead {
        fail("\(settingsURL.path) changed while this was running; nothing was written. Run it again.")
    } catch {
        fail("could not write \(settingsURL.path): \(error); the original is unchanged")
    }
    exit(0)
}

/// Hooks that run hook-me-up from another place (another copy of the app) stay, but
/// each request would then be notified twice: say so, and how to remove them.
private func warnAboutOtherInstallations(in settings: JSONValue, settingsURL: URL, hookPath: String) {
    let found = SettingsMerger.inspect(
        settings: settings, hookPath: hookPath, canonicalPath: AppLocation.resolvingSymlinks)
    guard !found.otherPaths.isEmpty else { return }
    let removals = Doctor.otherHookRemovals(
        found.otherPaths, setup: Bundle.main.executablePath ?? "hook-me-up-setup", settings: settingsURL.path)
    var lines = [
        "Warning: \(settingsURL.path) also runs hook-me-up from another place:"
    ]
    lines += found.otherPaths.map { "  " + $0 }
    lines += [
        "That looks like another installation. Its hooks are left as they are, but with both,",
        "every request is notified twice.",
    ]
    if !removals.commands.isEmpty {
        lines.append("If that copy is gone or unused, remove its hooks with:")
        lines += removals.commands.map { "  " + $0 }
    }
    if !removals.byHand.isEmpty {
        lines.append(
            removals.commands.isEmpty
                ? "If that copy is gone or unused, remove by hand from \(settingsURL.path):"
                : "Remove by hand from \(settingsURL.path):")
        lines += removals.byHand.map { "  " + $0 }
    }
    print(lines.joined(separator: "\n") + "\n")
}
