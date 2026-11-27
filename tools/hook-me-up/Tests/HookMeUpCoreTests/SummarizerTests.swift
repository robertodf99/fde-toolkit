import Foundation
import Testing

@testable import HookMeUpCore

private let project = ProjectInfo(name: "proj", gitRoot: "/home/me/proj", branch: "main", worktree: nil)
private let home = "/home/me"

private func request(_ tool: String, _ toolInput: String, cwd: String = "/home/me/proj/sub", extra: String = "") throws
    -> HookInput
{
    try parse(
        #"{"session_id":"s","cwd":"\#(cwd)","hook_event_name":"PermissionRequest","tool_name":"\#(tool)","tool_input":\#(toolInput)\#(extra)}"#
    )
}

private func summarize(_ input: HookInput) -> RequestSummary {
    Summarizer.summarize(input, project: project, home: home)
}

private func bash(_ command: String, description: String? = nil) throws -> RequestSummary {
    var fields: [String: JSONValue] = ["command": .string(command)]
    if let description { fields["description"] = .string(description) }
    let toolInput = String(decoding: try JSONEncoder().encode(JSONValue.object(fields)), as: UTF8.self)
    return summarize(try request("Bash", toolInput))
}

@Suite struct SummarizerTests {
    // MARK: Bash

    @Test func bashUsesDescription() throws {
        let summary = try bash("touch notes.txt", description: "Create empty notes.txt file")
        #expect(summary.kind == .permission)
        #expect(summary.title == "Run a command")
        #expect(summary.description == "Create empty notes.txt file")
    }

    @Test func bashWithoutDescriptionUsesTruncatedCommand() throws {
        let long =
            "swift build -c release --product hook-me-up && " + String(repeating: "echo filler ", count: 20)
        let summary = try bash(long + "\nsecond line")
        #expect(summary.description.count <= 120 && summary.description.count >= 110)
        #expect(summary.description.hasSuffix("…"))
        #expect(summary.description.hasPrefix("swift build -c release --product hook-me-up && echo filler"))
        #expect(!summary.description.contains("\n"))
        #expect(try bash("ls -la").description == "ls -la")
    }

    @Test func gitPushTagged() throws {
        let summary = try bash("git push -u origin claude/uc06", description: "Push branch")
        #expect(summary.tags.contains(.gitPush))
        #expect(summary.tags.contains(.network))
        #expect(summary.title == "Push to a remote repository")
        #expect(try bash("git -C /home/me/proj push").tags.contains(.gitPush))
        #expect(try bash("cd x && git push --force").tags.contains(.gitPush))
        #expect(!(try bash("git status && git log --oneline").tags.contains(.gitPush)))
        #expect(!(try bash("echo git push").tags.contains(.gitPush)))
    }

    @Test func curlTaggedNetwork() throws {
        #expect(try bash("curl -s https://example.com | jq .").tags.contains(.network))
        #expect(try bash("wget http://x.y/z").tags.contains(.network))
        #expect(try bash("npm install left-pad").tags.contains(.network))
        #expect(try bash("FOO=1 sudo -E pip install requests").tags.contains(.network))
        #expect(!(try bash("swift test").tags.contains(.network)))
    }

    @Test func rmTaggedDeletes() throws {
        let summary = try bash("rm -rf node_modules", description: "Remove node_modules directory")
        #expect(summary.tags.contains(.deletesFiles))
        #expect(summary.title == "Delete files")
        #expect(try bash("find . -name '*.tmp' -delete").tags.contains(.deletesFiles))
        #expect(try bash("git clean -fdx").tags.contains(.deletesFiles))
        #expect(try bash("git reset --hard HEAD~1").tags.contains(.deletesFiles))
        #expect(try bash("ls | xargs rm").tags.contains(.deletesFiles))
        #expect(try bash("git rm old.txt").tags.contains(.deletesFiles))
        #expect(!(try bash("ls -la").tags.contains(.deletesFiles)))
    }

    @Test func redirectOutsideProjectTagged() throws {
        #expect(try bash("echo hi > /etc/hosts").tags.contains(.writesOutsideProject))
        #expect(try bash("echo hi >> ../../elsewhere/log.txt").tags.contains(.writesOutsideProject))
        #expect(try bash("date | tee -a ~/notes.txt").tags.contains(.writesOutsideProject))
        #expect(try bash("cp build/app /usr/local/bin/app").tags.contains(.writesOutsideProject))
        #expect(!(try bash("echo hi > out.txt").tags.contains(.writesOutsideProject)))
        #expect(!(try bash("echo hi > ../sibling-in-project.txt").tags.contains(.writesOutsideProject)))
        #expect(!(try bash("make 2>/dev/null >/dev/null").tags.contains(.writesOutsideProject)))
        #expect(!(try bash("swift test 2>&1 | tail").tags.contains(.writesOutsideProject)))
    }

    /// Only warnings are tags: plain reads and writes inside the project have none.
    @Test func plainCommandsHaveNoTags() throws {
        #expect(try bash("git status && git diff | head").tags.isEmpty)
        #expect(try bash("mkdir -p build/tmp && touch build/tmp/x").tags.isEmpty)
        #expect(try bash("echo hi > out.txt").tags.isEmpty)
        #expect(try bash("rm x").tags == [.deletesFiles])
        #expect(try bash("git status; curl https://x.y").tags == [.network])
    }

    @Test func quotedOperatorsAreNotRedirectsOrSeparators() throws {
        #expect(try bash(#"git commit -m "fix: a > b; rm nothing""#).tags.isEmpty)
        #expect(try bash("git commit -m 'x > /etc/hosts'").tags.isEmpty)
        #expect(try bash(#"cat <<'EOF' > notes.md"#).tags.isEmpty)
        #expect(try bash("ls 1>&2").tags.isEmpty)
        // Command substitution runs even inside double quotes, so it is analysed too:
        // a hidden rm is still flagged.
        #expect(try bash(#"echo "$(rm -rf build)""#).tags == [.deletesFiles])
        #expect(try bash("echo \"`rm x`\"").tags == [.deletesFiles])
        #expect(try bash(#"echo "today: $(date)""#).tags.isEmpty)
        #expect(try bash(#"(cd sub && rm -f x); ls"#).tags == [.deletesFiles])
    }

    @Test func hiddenWritesAndConnectionsAreTagged() throws {
        let sortOut = try bash("sort -o ~/.zshrc notes.txt")
        #expect(sortOut.tags.contains(.writesOutsideProject))
        let fprint = try bash("find . -name '*.txt' -fprint0 /etc/out")
        #expect(fprint.tags.contains(.writesOutsideProject))
        #expect(try bash("tree -o /tmp/tree.txt").tags.contains(.writesOutsideProject))
        let tcp = try bash("echo hi > /dev/tcp/1.2.3.4/80")
        #expect(tcp.tags.contains(.network))
        #expect(try bash("cat < /dev/udp/1.2.3.4/53").tags.contains(.network))
        // Plain reads have no tags.
        #expect(try bash("sort notes.txt | uniq -c").tags.isEmpty)
        #expect(try bash("tree -L 2").tags.isEmpty)
    }

    @Test func outputOptionsWritingOutsideAreTagged() throws {
        #expect(try bash("uniq in.txt /home/x/.zshrc").tags.contains(.writesOutsideProject))
        #expect(try bash("git diff --output=/home/x/.zshrc").tags.contains(.writesOutsideProject))
        #expect(try bash("sort -uo /home/x/.zshrc a").tags.contains(.writesOutsideProject))
        // Plain reads have no tags.
        #expect(try bash("uniq -c in.txt").tags.isEmpty)
        #expect(try bash("rg -n foo src").tags.isEmpty)
        #expect(try bash("git diff --stat").tags.isEmpty)
        #expect(try bash("date +%Y").tags.isEmpty)
    }

    // MARK: Files

    @Test func editCountsChangedLinesRelativePath() throws {
        let input = try request(
            "Edit",
            #"""
            {"file_path":"/home/me/proj/Sources/App/main.swift",
             "old_string":"let a = 1\nlet b = 2\nlet c = 3",
             "new_string":"let a = 1\nlet b = 20\nlet c = 30\nlet d = 4"}
            """#)
        let summary = summarize(input)
        #expect(summary.title == "Edit a file")
        #expect(summary.description == "Change 3 lines in Sources/App/main.swift")
        #expect(summary.tags.isEmpty)

        let one = try request(
            "Edit", #"{"file_path":"/home/me/proj/README.md","old_string":"Helo","new_string":"Hello"}"#)
        #expect(summarize(one).description == "Change 1 line in README.md")
    }

    @Test func writeOutsideProjectTagged() throws {
        let outside = summarize(try request("Write", #"{"file_path":"/home/me/.zshrc","content":"a\nb\n"}"#))
        #expect(outside.tags == [.writesOutsideProject])
        #expect(outside.description == "Write 2 lines to ~/.zshrc")
        #expect(outside.title == "Write a file")

        let inside = summarize(try request("Write", #"{"file_path":"/home/me/proj/docs/a.md","content":"x"}"#))
        #expect(inside.tags.isEmpty)
        #expect(inside.description == "Write 1 line to docs/a.md")

        // Sibling folder sharing the prefix is still outside.
        let sibling = summarize(try request("Write", #"{"file_path":"/home/me/proj2/x","content":""}"#))
        #expect(sibling.tags == [.writesOutsideProject])
        // /tmp and /private/tmp are the same place.
        let tmpProject = ProjectInfo(name: "acme-api", gitRoot: "/private/tmp/acme-api", branch: nil, worktree: nil)
        let tmpWrite = Summarizer.summarize(
            try request("Write", #"{"file_path":"/tmp/acme-api/x.txt","content":"x"}"#, cwd: "/private/tmp/acme-api"),
            project: tmpProject, home: home)
        #expect(tmpWrite.tags.isEmpty)
        #expect(tmpWrite.description == "Write 1 line to x.txt")
    }

    // MARK: Web, MCP, others

    @Test func webFetchShowsHost() throws {
        let summary = summarize(
            try request("WebFetch", #"{"url":"https://docs.example.com/a/b?q=1","prompt":"summarise"}"#))
        #expect(summary.title == "Fetch a web page")
        #expect(summary.description == "docs.example.com")
        #expect(summary.tags == [.network])
    }

    @Test func mcpHumanized() throws {
        let summary = summarize(try request("mcp__linear__save_issue", #"{"title":"Fix login"}"#))
        #expect(summary.title == "Linear · Save issue")
        #expect(summary.description == "title: Fix login")
        #expect(
            summarize(try request("mcp__claude_ai_Google_Drive__searchFiles", "{}")).title
                == "Google Drive · Search files")
    }

    @Test func unknownToolFirstField() throws {
        let summary = summarize(try request("Frobnicate", #"{"zeta":"z","alpha":"a","count":3}"#))
        #expect(summary.title == "Frobnicate")
        #expect(summary.description == "alpha: a")
        #expect(
            summarize(try request("Glob", #"{"path":"/home/me/proj","pattern":"**/*.swift"}"#)).description
                == "pattern: **/*.swift")
        #expect(summarize(try request("Nothing", "{}")).description == "")
    }

    @Test func askUserQuestionKindQuestion() throws {
        let summary = summarize(
            try request(
                "AskUserQuestion",
                #"""
                {"questions":[{"question":"Which colour?","header":"Colour","options":[{"label":"Blue"}],"multiSelect":false},
                              {"question":"Which size?","header":"Size","options":[{"label":"S"}],"multiSelect":false}]}
                """#))
        #expect(summary.kind == .question)
        #expect(summary.title == "Which colour?")
        #expect(summary.description == "Claude is asking you 2 questions")
    }

    @Test func exitPlanModeKindPlan() throws {
        let summary = summarize(
            try request(
                "ExitPlanMode", #"{"plan":"\n# Plan: create hello.txt\n\n## Steps\n1. x\n","planFilePath":"/p.md"}"#))
        #expect(summary.kind == .plan)
        #expect(summary.title == "Review Claude's plan")
        #expect(summary.description == "Plan: create hello.txt")
    }

    @Test func subagentOriginWhenAgentIDPresent() throws {
        let sub = summarize(
            try request("Bash", #"{"command":"ls"}"#, extra: #","agent_id":"a1","agent_type":"Explore""#))
        #expect(sub.origin == .subagent)
        #expect(try bash("ls").origin == nil)
    }

    // MARK: Notifications and Stop

    @Test func notificationBecomesWaiting() throws {
        let summary = summarize(
            try parse(
                #"""
                {"session_id":"s","cwd":"/home/me/proj","hook_event_name":"Notification","message":"Claude needs your input on a form","notification_type":"elicitation_dialog"}
                """#))
        #expect(summary.kind == .waiting)
        #expect(summary.title == "Waiting for your reply")
        #expect(summary.description == "Claude needs your input on a form")
    }

    @Test func stopBecomesFinishedWithFirstSentenceGist() throws {
        func finished(_ message: String) throws -> RequestSummary {
            let json = String(
                decoding: try JSONEncoder().encode(
                    JSONValue.object([
                        "session_id": "s", "cwd": "/home/me/proj", "hook_event_name": "Stop",
                        "stop_hook_active": .bool(false), "last_assistant_message": .string(message),
                    ])), as: UTF8.self)
            return summarize(try parse(json))
        }
        let summary = try finished("I've completed the refactoring. Here's a summary of v1.2 changes...")
        #expect(summary.kind == .finished)
        #expect(summary.title == "Finished")
        #expect(summary.description == "I've completed the refactoring.")

        #expect(
            try finished("## Summary\n\n**All 42 tests pass** on `main`! Next steps follow.").description
                == "All 42 tests pass on main!")
        #expect(try finished("Updated main.swift and v1.2 notes").description == "Updated main.swift and v1.2 notes")

        let long = try finished(String(repeating: "word ", count: 60) + "end.")
        #expect(long.description.count <= 140 && long.description.count >= 130)
        #expect(long.description.hasSuffix("…"))
        #expect(try finished("").description == "")
    }
}

@Suite struct CodexPatchTests {
    @Test func patchPathsAndOutsideProject() throws {
        let patch =
            "*** Begin Patch\n*** Add File: added.txt\n+hello\n*** Update File: ../../outside.txt\n@@\n-x\n+y\n*** Delete File: old.txt\n*** End Patch"
        let json = JSONValue.object(["patch": .string(patch)])
        let encoded = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        let summary = summarize(try request("apply_patch", encoded))
        #expect(summary.title == "Apply a patch")
        #expect(summary.description.contains("added.txt"))
        #expect(summary.description.contains("outside.txt"))
        #expect(summary.description.contains("old.txt"))
        #expect(summary.tags.contains(.writesOutsideProject))
        let inside = summarize(try request("apply_patch", #"{"patch":"*** Add File: inside.txt"}"#))
        #expect(!inside.tags.contains(.writesOutsideProject))
    }
}
