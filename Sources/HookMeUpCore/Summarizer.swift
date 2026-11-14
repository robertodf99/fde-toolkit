import Foundation

/// Builds the notification text for a hook input: functional title, plain-language
/// description and rule-based warning tags. No LLM call, no I/O.
public enum Summarizer {
    static let descriptionLimit = 120
    static let gistLimit = 140

    /// The notification text for `input`. `home` is the user's home folder, used to
    /// shorten paths and to tell writes outside the project.
    public static func summarize(_ input: HookInput, project: ProjectInfo, home: String) -> RequestSummary {
        let origin: OriginTag? = input.agentID != nil ? .subagent : nil

        switch input.hookEventName {
        case "Stop":
            let message = input.raw["last_assistant_message"]?.stringValue ?? ""
            return RequestSummary(
                kind: .finished, title: "Finished", description: gist(message),
                tags: [], origin: origin)
        case "Notification":
            let message = input.message ?? ""
            return RequestSummary(
                kind: .waiting, title: "Waiting for your reply",
                description: oneLine(message, limit: gistLimit),
                tags: [], origin: origin)
        default:
            break
        }

        let paths = PathContext(root: project.gitRoot ?? input.cwd, cwd: input.cwd, home: home)
        let toolInput = input.toolInput ?? .object([:])
        let part = toolSummary(toolName: input.toolName ?? "", toolInput: toolInput, paths: paths)
        return RequestSummary(
            kind: part.kind, title: part.title, description: part.description,
            tags: EffectTag.ordered(part.tags), origin: origin)
    }

    // MARK: Per tool

    private struct Part {
        var kind: EntryKind = .permission
        var title: String
        var description: String
        var tags: Set<EffectTag> = []
    }

    private static func toolSummary(toolName: String, toolInput: JSONValue, paths: PathContext) -> Part {
        func string(_ key: String) -> String? { toolInput[key]?.stringValue }

        switch toolName {
        case "Bash":
            let command = string("command") ?? ""
            let tags = bashTags(command, paths: paths)
            let title =
                tags.contains(.gitPush)
                ? "Push to a remote repository"
                : tags.contains(.deletesFiles)
                    ? "Delete files"
                    : "Run a command"
            let described = oneLine(string("description") ?? "", limit: descriptionLimit)
            return Part(
                title: title, description: described.isEmpty ? oneLine(command, limit: descriptionLimit) : described,
                tags: tags)

        case "Edit", "MultiEdit":
            guard let file = string("file_path") else { break }
            let changed: Int
            if let edits = toolInput["edits"]?.arrayValue {
                changed = edits.reduce(0) { total, edit in
                    total
                        + changedLines(
                            old: edit["old_string"]?.stringValue ?? "", new: edit["new_string"]?.stringValue ?? "")
                }
            } else {
                changed = changedLines(old: string("old_string") ?? "", new: string("new_string") ?? "")
            }
            return Part(
                title: "Edit a file", description: "Change \(lines(changed)) in \(paths.display(file))",
                tags: paths.isInside(file) ? [] : [.writesOutsideProject])

        case "Write":
            guard let file = string("file_path") else { break }
            return Part(
                title: "Write a file",
                description: "Write \(lines(lineCount(string("content") ?? ""))) to \(paths.display(file))",
                tags: paths.isInside(file) ? [] : [.writesOutsideProject])

        case "NotebookEdit":
            guard let file = string("notebook_path") else { break }
            return Part(
                title: "Edit a notebook", description: "Change a cell in \(paths.display(file))",
                tags: paths.isInside(file) ? [] : [.writesOutsideProject])

        case "WebFetch":
            let url = string("url") ?? ""
            let host = URL(string: url)?.host ?? oneLine(url, limit: descriptionLimit)
            return Part(title: "Fetch a web page", description: host, tags: [.network])

        case "WebSearch":
            return Part(
                title: "Search the web", description: oneLine(string("query") ?? "", limit: descriptionLimit),
                tags: [.network])

        case "AskUserQuestion":
            let questions = toolInput["questions"]?.arrayValue ?? []
            let first = questions.first?["question"]?.stringValue.map { oneLine($0, limit: gistLimit) } ?? ""
            let count = questions.count
            return Part(
                kind: .question,
                title: first.isEmpty ? "Claude has a question" : first,
                description: count > 1 ? "Claude is asking you \(count) questions" : "Claude is asking you a question")

        case "ExitPlanMode":
            let plan = string("plan") ?? ""
            let firstLine =
                plan.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            let heading = firstLine.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            return Part(
                kind: .plan, title: "Review Claude's plan",
                description: oneLine(cleanInline(heading), limit: gistLimit))

        default:
            if let title = humanizedMCPName(toolName) {
                return Part(title: title, description: firstField(toolInput))
            }
        }
        return Part(title: toolName.isEmpty ? "Use a tool" : toolName, description: firstField(toolInput))
    }

    // MARK: Bash effect tags

    private static let networkCommands: Set<String> = [
        "curl", "wget", "ssh", "scp", "sftp", "nc", "ncat", "telnet", "ftp", "http", "https", "xh",
        "ping", "dig", "nslookup", "host", "gh", "aws", "gcloud", "az", "kubectl", "helm", "npx",
        "bunx", "pnpx", "railway", "vercel", "flyctl", "fly", "heroku", "supabase", "netlify",
    ]
    /// Package managers and the subcommands that download or publish.
    private static let networkSubcommands: [String: Set<String>] = [
        "npm": ["install", "i", "ci", "add", "update", "publish", "exec", "dlx", "view", "info", "audit"],
        "pnpm": ["install", "i", "add", "update", "publish", "dlx", "exec"],
        "yarn": ["install", "add", "upgrade", "publish", "dlx"],
        "bun": ["install", "i", "add", "update", "publish", "x"],
        "pip": ["install", "download"], "pip3": ["install", "download"],
        "uv": ["pip", "sync", "add", "lock", "run", "tool"],
        "brew": ["install", "update", "upgrade", "tap", "fetch", "reinstall"],
        "gem": ["install", "update", "push"],
        "cargo": ["install", "publish", "fetch", "add", "update", "search"],
        "go": ["get", "install", "mod"],
        "docker": ["pull", "push", "login", "search"],
        "podman": ["pull", "push", "login", "search"],
        "git": ["push", "pull", "fetch", "clone", "ls-remote", "submodule"],
        "rsync": [], "terraform": ["apply", "plan", "init", "destroy"],
    ]
    private static let urlSchemes = ["http://", "https://", "ftp://", "ssh://", "git://", "ws://", "wss://"]
    private static let deleteCommands: Set<String> = ["rm", "rmdir", "unlink", "shred", "srm", "trash"]
    private static let pathWritingCommands: Set<String> = [
        "rm", "rmdir", "unlink", "shred", "touch", "mkdir", "chmod", "chown", "truncate", "trash",
    ]
    private static let copyCommands: Set<String> = ["cp", "mv", "install", "ln", "rsync", "ditto"]
    static func bashTags(_ command: String, paths: PathContext) -> Set<EffectTag> {
        let parsed = ShellCommand(command)
        var tags = Set<EffectTag>()

        if urlSchemes.contains(where: command.lowercased().contains) { tags.insert(.network) }

        for segment in parsed.segments {
            let args = segment.args
            for redirect in segment.redirects {
                let target = redirect.target
                // bash opens a network connection for /dev/tcp and /dev/udp.
                if target.hasPrefix("/dev/tcp/") || target.hasPrefix("/dev/udp/") {
                    tags.insert(.network)
                    continue
                }
                guard redirect.op.contains(">"), !target.hasPrefix("&"), !target.hasPrefix("/dev/") else { continue }
                if !paths.isInside(target) { tags.insert(.writesOutsideProject) }
            }

            guard let name = segment.name else { continue }
            let operands = args.filter { !$0.hasPrefix("-") }

            if networkCommands.contains(name) { tags.insert(.network) }
            if let subcommands = networkSubcommands[name], name != "git" {
                if subcommands.isEmpty || operands.first.map(subcommands.contains) == true { tags.insert(.network) }
            }
            if name == "rsync", operands.contains(where: { $0.contains(":") }) { tags.insert(.network) }
            if deleteCommands.contains(name) { tags.insert(.deletesFiles) }
            if name == "find" {
                if args.contains("-delete") { tags.insert(.deletesFiles) }
                for (index, arg) in args.enumerated() where ["-exec", "-execdir", "-ok", "-okdir"].contains(arg) {
                    if index + 1 < args.count, deleteCommands.contains((args[index + 1] as NSString).lastPathComponent)
                    {
                        tags.insert(.deletesFiles)
                    }
                }
                for (index, arg) in args.enumerated() where ["-fprint", "-fprint0", "-fprintf", "-fls"].contains(arg) {
                    if index + 1 < args.count, !paths.isInside(args[index + 1]) { tags.insert(.writesOutsideProject) }
                }
            } else if name == "git" {
                let git = gitSubcommand(args)
                if let sub = git.sub {
                    let rest = git.rest
                    if networkSubcommands["git"]?.contains(sub) == true { tags.insert(.network) }
                    if sub == "push" { tags.insert(.gitPush) }
                    if gitDeletes(sub, rest) { tags.insert(.deletesFiles) }
                    // --output writes a file.
                    for target in optionValues(args, short: "-O", long: "--output") ?? []
                    where args.contains(where: { $0.hasPrefix("--output") }) && !paths.isInside(target) {
                        tags.insert(.writesOutsideProject)
                    }
                }
            } else if name == "sort" {
                // -o FILE, -uo FILE (combined flags), --output=FILE write a file.
                let outputs = sortOutputs(args)
                for target in outputs where !paths.isInside(target) { tags.insert(.writesOutsideProject) }
            } else if name == "tree" {
                let outputs = optionValues(args, short: "-o", long: nil)
                for target in outputs ?? [] where !paths.isInside(target) { tags.insert(.writesOutsideProject) }
            } else if name == "uniq" {
                // uniq IN OUT writes OUT.
                if operands.count >= 2, !paths.isInside(operands[1]) { tags.insert(.writesOutsideProject) }
            }

            if name == "tee" {
                for target in operands where !paths.isInside(target) { tags.insert(.writesOutsideProject) }
            }
            if pathWritingCommands.contains(name) {
                for target in operands where !paths.isInside(target) { tags.insert(.writesOutsideProject) }
            }
            if copyCommands.contains(name), operands.count >= 2, let destination = operands.last,
                !destination.contains(":") || name != "rsync", !paths.isInside(destination)
            {
                tags.insert(.writesOutsideProject)
            }
            if name == "dd" {
                for arg in args where arg.hasPrefix("of=") && !paths.isInside(String(arg.dropFirst(3))) {
                    tags.insert(.writesOutsideProject)
                }
            }
        }
        return tags
    }

    /// Output files of sort: -o FILE, -oFILE, -uo FILE / -uoFILE (combined short flags),
    /// --output=FILE, --output FILE.
    private static func sortOutputs(_ args: [String]) -> [String] {
        var outputs: [String] = []
        for (index, arg) in args.enumerated() {
            if arg == "--output", index + 1 < args.count {
                outputs.append(args[index + 1])
            } else if arg.hasPrefix("--output=") {
                outputs.append(String(arg.dropFirst("--output=".count)))
            } else if arg.hasPrefix("-"), !arg.hasPrefix("--"), let o = arg.dropFirst().firstIndex(of: "o") {
                let attached = String(arg[arg.index(after: o)...])
                if !attached.isEmpty {
                    outputs.append(attached)
                } else if index + 1 < args.count {
                    outputs.append(args[index + 1])
                }
            }
        }
        return outputs
    }

    /// Values of an output option (`-o FILE`, `-oFILE`, `--output=FILE`, `--output FILE`);
    /// nil when the option is absent.
    private static func optionValues(_ args: [String], short: String, long: String?) -> [String]? {
        var values: [String] = []
        var found = false
        for (index, arg) in args.enumerated() {
            if arg == short || (long != nil && arg == long) {
                found = true
                if index + 1 < args.count { values.append(args[index + 1]) }
            } else if let long, arg.hasPrefix(long + "=") {
                found = true
                values.append(String(arg.dropFirst(long.count + 1)))
            } else if arg.hasPrefix(short), arg.count > short.count, !arg.hasPrefix("--") {
                found = true
                values.append(String(arg.dropFirst(short.count)))
            }
        }
        return found ? values : nil
    }

    /// git's subcommand after global options (-C <path>, -c <k=v>, --git-dir=..., ...).
    private static func gitSubcommand(_ args: [String]) -> (sub: String?, rest: [String]) {
        var index = 0
        while index < args.count, args[index].hasPrefix("-") {
            if ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"].contains(
                args[index])
            {
                index += 1
            }
            index += 1
        }
        guard index < args.count else { return (nil, []) }
        return (args[index], Array(args[(index + 1)...]))
    }

    private static func gitDeletes(_ sub: String, _ rest: [String]) -> Bool {
        switch sub {
        case "clean", "rm": return true
        case "reset": return rest.contains("--hard")
        case "checkout": return rest.contains("--") || rest.contains(".")
        case "restore": return !rest.contains("--staged")
        case "branch": return rest.contains { ["-d", "-D", "--delete"].contains($0) }
        case "stash": return rest.first.map { ["drop", "clear"].contains($0) } ?? false
        case "worktree": return rest.first == "remove"
        default: return false
        }
    }

    // MARK: Text helpers

    static func changedLines(old: String, new: String) -> Int {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        return max(1, max(a.count - prefix - suffix, b.count - prefix - suffix))
    }

    static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts.count
    }

    private static func lines(_ count: Int) -> String { count == 1 ? "1 line" : "\(count) lines" }

    /// Whitespace (including newlines) collapsed to single spaces, then truncated.
    static func oneLine(_ text: String, limit: Int) -> String {
        truncate(text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " "), limit: limit)
    }

    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit - 1))
        while cut.last?.isWhitespace == true { cut.removeLast() }
        return cut + "…"
    }

    /// Markdown emphasis and code markers removed, whitespace collapsed.
    static func cleanInline(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// First sentence of the first paragraph of Claude's last message (headings, code
    /// fences and list markers skipped), at most 140 characters.
    static func gist(_ message: String) -> String {
        var paragraph: [String] = []
        var heading: String?
        var inFence = false
        for rawLine in message.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                if !paragraph.isEmpty { break }
                continue
            }
            if inFence { continue }
            if line.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            if line.hasPrefix("#") {
                if !paragraph.isEmpty { break }
                if heading == nil { heading = String(line.drop { $0 == "#" }) }
                continue
            }
            let item = stripListMarker(line)
            if !paragraph.isEmpty && item != line { break }  // next list item
            paragraph.append(item)
        }
        let text = cleanInline(paragraph.isEmpty ? (heading ?? "") : paragraph.joined(separator: " "))
        return truncate(firstSentence(text), limit: gistLimit)
    }

    private static func stripListMarker(_ line: String) -> String {
        for marker in ["- ", "* ", "+ ", "> "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return String(rest.dropFirst(2)) }
        }
        return line
    }

    private static func firstSentence(_ text: String) -> String {
        let chars = Array(text)
        for (index, char) in chars.enumerated() where ".!?".contains(char) {
            if index + 1 == chars.count || chars[index + 1].isWhitespace {
                return String(chars[...index])
            }
        }
        return text
    }

    // MARK: MCP and other tools

    /// `mcp__linear__save_issue` -> "Linear · Save issue".
    static func humanizedMCPName(_ toolName: String) -> String? {
        guard toolName.hasPrefix("mcp__") else { return nil }
        let rest = toolName.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__") else { return nil }
        var server = String(rest[..<separator.lowerBound])
        let tool = String(rest[separator.upperBound...])
        for prefix in ["claude_ai_", "plugin_"] where server.hasPrefix(prefix) { server.removeFirst(prefix.count) }
        let serverWords = words(server).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let toolWords = words(tool).map { $0.lowercased() }
        guard !serverWords.isEmpty, let firstToolWord = toolWords.first else { return nil }
        let toolText = ([firstToolWord.prefix(1).uppercased() + firstToolWord.dropFirst()] + toolWords.dropFirst())
            .joined(separator: " ")
        return serverWords.joined(separator: " ") + " · " + toolText
    }

    /// Splits snake_case, kebab-case and camelCase into words.
    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previousIsLower = false
        for char in text {
            if char == "_" || char == "-" || char == " " {
                if !current.isEmpty { result.append(current) }
                current = ""
                previousIsLower = false
                continue
            }
            if char.isUppercase, previousIsLower, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(char)
            previousIsLower = char.isLowercase || char.isNumber
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static let preferredFields = [
        "command", "file_path", "notebook_path", "url", "pattern", "query", "prompt", "path",
        "description", "subject", "title", "name",
    ]

    /// "key: value" for the most telling string field: a well-known key first, else the
    /// alphabetically first string field (JSON object order is not preserved).
    static func firstField(_ toolInput: JSONValue) -> String {
        guard let object = toolInput.objectValue else { return "" }
        let stringKeys = object.keys.filter { object[$0]?.stringValue != nil }
        guard let key = preferredFields.first(where: stringKeys.contains) ?? stringKeys.sorted().first,
            let value = object[key]?.stringValue
        else { return "" }
        return oneLine("\(key): \(value)", limit: descriptionLimit)
    }
}
