# Architecture

Hook Me Up is two processes: a short-lived **hook** that Claude Code runs for each
event, and a long-running menu-bar **agent** that shows native notifications. They talk
over a Unix socket. Everything else is libraries, so the logic is tested without a UI.

## Modules

| Module | Kind | Responsibility |
|---|---|---|
| `HookMeUpCore` | library | Pure domain logic on Foundation, no I/O of its own: hook input parsing, the plain-language `Summarizer`, `DecisionEncoder`, `SessionPermissionFilter`, wire messages and `Framing`, the agent's routing reducer `AgentCore` with `PendingStore`, the notification mapping `NativeNotification`, terminal mapping, `SessionActivation` (how a click brings a session forward: tab, Ghostty terminal, project window or app), `GhosttyTerminals` (the fixed Ghostty scripts, which listed terminal is in the session's folder, and the title marker: token, OSC 2 sequence, sanitised titles, tty device path), `EditorWindows` (which open VS Code-family window contains a session's folder, read from the editor's `storage.json`) and `EditorExtension` (whether an editor has Hook Me Up's extension, from its `extensions.json`, when to ask it, and the request it is sent). File reads go through the injected `FileSystem` protocol. |
| `HookMeUpIPC` | library | Socket transport: `SocketServer` (with its periodic socket check, `SocketCheck`), `SocketClient`, `Connection` and the file-system/peer checks. |
| `HookKit` | library | The hook runner `runHook`: parse, summarise, ask the agent, encode the decision. |
| `AgentKit` | library | The agent runtime `AgentController`: socket ↔ `AgentCore` ↔ notifications, behind the protocols `NotificationPresenting`, `TerminalActivating` and `WallClock`. |
| `SetupKit` | library | The installer: `SettingsMerger` (add/remove our hooks, matched by the binary their command runs, and `inspect`: which of them a settings file has and how they differ from what install writes), `SettingsFile` (backup, atomic write) and `AppLocation` (the app around an executable, the default `--hook`). |
| `DoctorKit` | library | `hook-me-up-setup doctor`: `Doctor` evaluates an installation (app, LaunchAgent, running agent, hooks, notification settings) through the `DoctorProbe` protocol and prints a fix for each problem; `AgentClient` asks the agent for its status over the socket; `NotificationOnboarding` (behind `OnboardingIO`) is the installer's notification check. |
| `hook-me-up` | executable | Reads stdin, calls `runHook`, prints its output; always exits 0. |
| `hook-me-up-setup` | executable | `install` / `uninstall` around SetupKit, `doctor` and `notifications` around DoctorKit. |
| `HookMeUp` | app | AppKit and UserNotifications adapters only: `AppDelegate`, `StatusMenu`, `UserNotificationPresenter`, `TerminalActivator` (with `SessionProbe`, `TTYWriter`, which writes a title marker to the session's own tty only, and `EditorRequestFile`, which writes the editor extension's request atomically). |
| `editor-extension/` | VS Code extension | Plain JavaScript, no dependencies, no build step (`scripts/build-vsix.sh` packs it): in every window of VS Code, VS Code Insiders, Cursor and Windsurf, watches the agent's request file and shows the integrated terminal whose process is one of the request's pids. Tested with Node and a stand-in for VS Code by `make editor-extension-check` (in CI too). |

Dependencies point inward: `HookMeUpCore` ← `HookMeUpIPC` ← `HookKit`, `AgentKit`;
`HookMeUpCore` ← `SetupKit`; `HookMeUpIPC`, `SetupKit` ← `DoctorKit`; the executables
sit at the edge. Each module has a test
target with the same name plus `Tests`.

## Data flow

1. Claude Code runs `hook-me-up permission --timeout 600` with the event JSON on
   stdin. The hook parses it, writes a summary, finds the project and the terminal
   (ancestor PIDs, tty), and keeps only session-scoped permission suggestions.
2. It connects to `~/Library/Application Support/hook-me-up/agent.sock` and sends a
   `request` with a fresh id, then waits (at most the handler timeout minus 10 s).
3. The agent reads the frame, checks notification permission, and `AgentCore` adds an
   entry. `NativeNotification` turns the entry into a `NotificationSpec` (title, body,
   category, buttons); the agent posts what changed through `NotificationPresenting`.
4. The user taps a button, replies or clicks. The response becomes a
   `NotificationOutcome`: a decision, an answer to the current question (several
   questions are asked one at a time), a hint, or Open session. `AgentCore` sends one
   `response` on that request's connection, closes it and the notification is removed.
5. The hook checks the response id, builds its stdout from its **own** input with
   `DecisionEncoder`, prints it and exits. Claude Code applies the decision.

"Open session" (a click on the notification body) runs `TerminalActivator` with the
session's place (ancestor PIDs, tty, folder). Off the main thread it finds the app,
plans (`SessionActivation`) and, for a VS Code-family editor with the extension, writes
the extension's request; on the main thread it focuses the tab, terminal or window, or
brings the app forward. Ghostty with several terminals in the session's folder: the
`titles` script lists every terminal's title, a fresh token is written as an OSC 2 title
to the session's tty (`TTYWriter`), the `findMarker` script (token as an argument) polls
Ghostty for up to a second for the terminal that shows it, that terminal's earlier title
is written back (an empty title when not exactly one terminal shows it, or when the
earlier title itself holds a marker, so a marker never stays), and only then is it
focused. Ghostty clicks run one at a time on their own serial queue, so two clicks close
together never mix their markers and titles. Editors: the request
(`editor-focus-request.json` in the support folder, `0600`, written to a temporary file
and renamed) holds a nonce, the click time and the session's pids up to the editor's own;
the window that has one of those pids as a terminal process shows it, and the window is
focused as before.

Heads-ups (`notify` for waiting/finished, `clear` when the session moves on) are
fire-and-forget. When the user answers in the terminal dialog instead, Claude Code does
not stop the waiting hook. The session moving on is the signal: on its `Stop`
(`notify` finished), `UserPromptSubmit` or `SessionEnd` (`clear`), the agent answers
each of that session's requests still waiting with `.paused` (the hook prints nothing),
closes the connection and removes the entry and its notification. No second decision
is ever sent, and no "Timed out" heads-up follows when the turn ends within ~590 s of
the request (a longer turn shows one until the turn ends or, while paused, until the
next prompt). This happens even while paused; `waiting` releases nothing. A request
connection that closes first (the hook is interrupted or its session process exits)
also removes its entry.

Known limitation: a request from a background subagent shares its parent's session id.
If the main turn ends or a new prompt is sent while that request is still unanswered,
its notification is withdrawn and it has to be answered in the terminal (fail-open:
nothing is decided).

`hook-me-up-setup doctor` and `hook-me-up-setup notifications` send a `statusQuery` on
the same socket (same client, UID check and framing). The agent answers with one
`status` (its version and build, the notification authorization and style, whether it
is paused, how many entries wait; never request content) and closes the connection,
without touching the entries. An agent from before status queries can't decode the
message and closes the connection without answering, which they report as an agent too
old to answer.

## Security model

- **Fail-open.** The hook prints a decision only for an explicit user decision. No
  agent, notifications off (requests already waiting are released at the next check:
  before each request, and every minute while something waits), pause, a question it cannot ask, any error, a timeout or a mismatched id:
  it prints nothing and exits 0, and Claude Code shows its terminal dialog.
- **UID-checked socket.** The socket lives in a `0700` directory owned by the user
  (opened with `O_NOFOLLOW`; symlinks and other owners are refused), is `0600`, and
  both sides verify the peer's UID with `getpeereid`.
- **The socket comes back.** Every ~5 s the agent checks that the file at the socket
  path is still its own socket (device and inode). When it is gone (removed, or its
  folder removed by a cleanup tool or an older uninstaller), the folder is prepared again
  with the same rules (created `0700`, its mode fixed) and a new socket is bound at the
  path: "socket was removed or replaced; listening again". A dead socket there is
  replaced; a live one belongs to another agent, so this one stops listening without
  removing anything and quits (exit 0, as at launch). Anything else (not a socket, a
  symlinked folder, another user's) is left untouched and logged once ("could not listen
  again: …"); the next checks try again. Connections already accepted keep working, and
  `stop()` removes only the socket the agent created last.
- **Request-id matching, one response per request.** The agent answers only on the
  request's own connection, at most once, and only while the entry is pending; the hook
  ignores a response for any other id. A notification response counts only under the
  category and buttons the entry shows now, and every answering button requires an
  unlocked Mac.
- **The hook owns the output.** `updatedInput` is built from the hook's own
  `tool_input`; answers must cover exactly the hook's own questions.
- **Session-only permissions.** "Approve for session" keeps only `addRules` (allow) and
  `addDirectories`, rebuilt with `destination: "session"`; nothing reaches the settings
  files.
- **Installer.** Shows the diff, asks, backs up, writes atomically, and refuses to
  write when the file changed since it was read.
- **A click writes only to the session's own terminal.** A title marker goes only to a
  tty named `ttysNNN`/`ttysNNNN`, only while the session's process runs and the tty is its
  controlling terminal: checked with `lstat` before opening and `fstat` after (a character
  device of this user, with the session's device number), opened `O_WRONLY | O_NOCTTY |
  O_NONBLOCK | O_NOFOLLOW`; one write, ended with BEL if it is cut short. The token
  (`hmu-` and 16 random hex digits) and Ghostty's ids go to the scripts as arguments,
  never as script text; titles written back lose control characters (C0, DEL, C1) and are
  cut at 255 bytes.
- **The editor request carries no content.** Only a nonce, a time and pids, written into
  the private support folder (refused unless it is this user's, not a link, closed to
  others), `0600`, atomically. The extension acts on a request only when it matches that
  format exactly, is less than 5 s old and its nonce is new; it never writes the file.
- **Logs** hold event kinds and short ids, never commands, messages or paths from the
  request, nor titles, ttys or tokens.

## Threading model

- **Hook:** single-threaded, blocking socket I/O with timeouts. A dispatch source
  watches the Claude Code process and interrupts the wait if it exits; `SIGTERM`
  leaves at once with status 0.
- **Agent:** everything runs on the main actor. `SocketServer` accepts on a private
  queue and hands each connection to the main queue, where `Connection` reads frames.
  The socket check is a timer on that same private queue; it changes the listener under
  the server's lock and reports what changed (`SocketCheck`) outside it, and
  `AgentController` logs it on the main actor.
  `AgentController` handles socket events and notification responses one at a time in
  arrival order (a chain of tasks), so a request waiting for its asynchronous
  authorization check can never be overtaken by its own connection closing.
  `AgentCore` and `PendingStore` are value types mutated only there.
- **UserNotifications** callbacks arrive on arbitrary queues; the presenter copies the
  `Sendable` parts and hops to the main actor. "Open session" runs AppleScript in an
  `osascript` child process off the main thread.
- The package builds in the Swift 6 language mode with strict concurrency and no
  warnings.

## Packaging and installation

- `scripts/build-app.sh` builds `HookMeUp.app` with the agent and both CLIs in
  `Contents/MacOS` (`UNIVERSAL=1` for arm64 + x86_64) and the editor extension as
  `Contents/Resources/hook-me-up.vsix` (built by `scripts/build-vsix.sh`: a zip with
  `[Content_Types].xml`, `extension.vsixmanifest` and `extension/`, made with `zip`, no
  npm or vsce; fixed timestamps, so the same sources give the same bytes), before the
  bundle is signed; `make dist` packages it as `hook-me-up-<version>-macos.zip` with a
  `.sha256`.
- A `v*` tag runs `.github/workflows/release.yml`: tests, a universal ad-hoc-signed
  package, checks, a build provenance attestation for the zip (`gh attestation verify`),
  and a GitHub release with the zip and checksum. The app icon is drawn
  at build time by `scripts/make-icon.swift` from the committed symbol path
  (`Resources/icon/claude-symbol.svg`). The project logo, GitHub's social preview and
  the Product Hunt thumbnail in `docs/images/` are drawn by `scripts/make-logo.swift`
  (`make logo`); the demo video (`.build/demo/hook-me-up-demo.mp4`) and the README's
  GIF by `scripts/make-demo.sh`, from screen recordings that are never committed (the
  shot list is a table at the top of the script).
- `install.sh` downloads that release (checksum verified), installs
  `~/Applications/Hook Me Up.app` exactly as packaged (its signature intact),
  adds the hooks only with consent (asked on `/dev/tty`, or `HOOK_ME_UP_YES=1`), and
  starts the agent with a LaunchAgent. Then it runs `hook-me-up-setup notifications`
  (when the package's setup has it, launchctl started the agent and
  `HOOK_ME_UP_NO_ONBOARDING` isn't set): status queries until macOS's notification
  question is answered, a `testNotification` (posted outside the entries, id
  `hook-me-up-test`, no buttons), and System Settings opened when notifications need
  changing. It never reads stdin and never fails the install. It also adds the editor
  extension with each editor's command-line tool it finds (`code`, `code-insiders`,
  `cursor`, `windsurf` on `PATH`, else inside the app in `/Applications` or
  `~/Applications`): `--install-extension <app>/Contents/Resources/hook-me-up.vsix
  --force`, at most 2 minutes each (then the tool and the editor process it started are stopped), never failing the install (`HOOK_ME_UP_NO_EDITOR_EXTENSION=1`
  skips it). `uninstall.sh` reverses it (`--uninstall-extension hook-me-up.hook-me-up`)
  and keeps the settings backups.
  `scripts/test-install.sh` runs both against a throwaway HOME, with system folders only
  on `PATH` and stand-ins for the editors' tools.
