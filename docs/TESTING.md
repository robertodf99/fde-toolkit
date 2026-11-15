# Testing Hook Me Up

## Automated

```sh
make test          # unit tests (Swift Testing)
make selftest      # the built hook with no agent: prints nothing, exits 0, quickly
make lint          # swift format lint
make test-install  # install.sh and uninstall.sh against a throwaway HOME
make signing-check # ad-hoc and identity signing, in a temporary folder
make plugin-check  # the Claude Code plugin's JSON manifests and skills
make editor-extension-check  # the editor extension's JavaScript with a stand-in for VS Code (needs node)
```

`HookMeUpTests` write title markers to a real pseudo-terminal (`openpty`) and read them
back from its other end, and check that `/dev/null`, a regular file, a symlink to the
terminal and another terminal are refused; read a process's controlling terminal (one
started by `script`); run the Ghostty title-marker steps against a stand-in for Ghostty
and the tty (titles, marker, find, title written back, focus, in that order; marker not
seen; a failed write; no tty); and write the editor request into private and other
folders (`0600`, atomic, never through a link, never into a folder others can reach).

`make editor-extension-check` runs `editor-extension/extension.js` under Node with a
stand-in for the `vscode` module: the request checks (format, age, nonce, pids, file and
folder owner and mode, links, size, FIFOs), which terminal is shown (the nearest pid; a
terminal that doesn't say its process id is skipped) and the watcher (once per request,
not for an old one, a folder created later). It is not part of CI (which has no Node);
run it after changing the extension.

`HookMeUpIPCTests` remove a running server's socket or its folder, recreate the folder
open, or put a file, a symlinked folder, a stale socket or another server's live socket
in its place, and check that it listens again (folder `0700`, socket `0600`, earlier
connections still answered), leaves what isn't its own untouched, or gives way; the
periodic check runs every 50 ms there.

`DoctorKitTests` run every doctor check against a fake `DoctorProbe` (each failure with
its fix and the exit code), the installer's notification check against a scripted
`OnboardingIO` (waiting, test notification, when System Settings opens), and the real
`AgentClient` against a socket server that answers, closes without answering (an older
agent) or never answers. `make test-install`
also runs `hook-me-up-setup doctor --home <throwaway HOME>`: app, LaunchAgent and hooks
are checked; launchd and the running agent are skipped there. For the notification check
it puts stand-ins for `launchctl`, `pgrep` and `open` first on `PATH` and replaces the
package's `hook-me-up-setup notifications` with a stand-in that records its flags (and
refuses unknown ones) and reports a given result: it checks the flags on a first install
(`--open-settings`) and an upgrade (`--open-settings-if-off`), `/dev/null` as stdin, the
next steps for ready, not-alerts, off and no-agent, and that the real command accepts
the same flags. It also checks that install.sh stops when it finds Homebrew's copy
(`HOOK_ME_UP_TEST_BREW_PREFIX` points it at a fake one) unless
`HOOK_ME_UP_IGNORE_HOMEBREW=1`, and that uninstall.sh keeps the support folder (and a
stand-in socket in it) next to that copy or a `sh.brew.hook-me-up.plist`, which it leaves
alone. For the editor extension, every run gets system folders only on `PATH` (it refuses
to run if a real `code`, `code-insiders`, `cursor` or `windsurf` is there) and a fake
Applications folder (`HOOK_ME_UP_TEST_APPLICATIONS`); a stand-in `code` (on `PATH`) and
`cursor` (inside a fake `Cursor.app`) record their flags: the app's `.vsix` installed
with `--force`, nothing with `HOOK_ME_UP_NO_EDITOR_EXTENSION=1`, a failing tool doesn't
fail the install, uninstall runs `--uninstall-extension hook-me-up.hook-me-up` except
next to Homebrew's copy, and with no tool at all both scripts say nothing about it. It
also checks that the installed app holds the `.vsix` with its six entries.

CI runs `lint`, `test`, `selftest`, `test-install` and `plugin-check` on every push and
pull request. With the claude CLI installed, `claude plugin validate .` and
`claude plugin validate ./plugins/hook-me-up` check the plugin further (expected: passed,
with a warning that no version is set; the version is left out on purpose, so users
get the plugin as it is on `main`).

## End-to-end checklist

Unit tests cover the logic; these checks need real notifications, real clicks and
real Claude Code sessions. Mark each line ✅ / ❌ with a note. Logs (event kinds and
short ids only, never commands or messages): `tail -f ~/Library/Logs/hook-me-up.log`, or
with Homebrew's service `tail -f "$(brew --prefix)/var/log/hook-me-up.log"`.

For each check, use a scratch repository and `claude --permission-mode default` unless
said otherwise, so that permission prompts actually appear.

## 0. Install and notification settings

1. Install with the one-liner from the README (or `make install` from a checkout). It
   shows the diff of `~/.claude/settings.json` and asks before writing (backup
   `settings.json.bak-<timestamp>` next to it). Expect only a new `hooks` block with
   five events: PermissionRequest (matcher `""`, timeout 600), Notification
   (`elicitation_dialog`), Stop, UserPromptSubmit, SessionEnd. The settings file is
   rewritten with sorted keys and 2-space indentation (same content; the backup keeps
   your original bytes). With VS Code (or VS Code Insiders, Cursor, Windsurf) installed,
   it says "Added the Hook Me Up extension to VS Code." and, in the next steps, to reload
   windows that were already open; `code --list-extensions` lists `hook-me-up.hook-me-up`.
   With `HOOK_ME_UP_NO_EDITOR_EXTENSION=1`: "Editor extension skipped
   (HOOK_ME_UP_NO_EDITOR_EXTENSION=1)." and nothing is added. Without any of those editors:
   "Editor extension skipped (no … command-line tool found)." and the install goes on.
2. Run the installer again: it reports no changes to the settings and replaces the app
   (that is how upgrades work).
3. System Settings → General → Login Items → Allow in the Background lists **Hook Me
   Up** with its icon (not "HookMeUp" with a generic icon), after a fresh install and
   after upgrading from 0.1.0. Optionally, `sfltool dumpbtm` shows the item with
   `io.github.robertodf99.hook-me-up` among its associated bundle identifiers.
4. macOS asks once to allow notifications from **Hook Me Up**. Meanwhile the installer
   prints "Waiting up to 60 s for your answer to macOS…" (10 s when it runs without a
   terminal). Allow → "Sent a test notification." and a "Hook Me Up" notification that
   says notifications work (with Banners it also says to set Alerts); clicking it
   opens nothing. On a first install with the style still Banners, System Settings
   opens at Notifications. **Check by hand on macOS 14, 15 and 26** whether the link
   (`x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.robertodf99.hook-me-up`)
   lands on Hook Me Up's own page or only on the Notifications list; note which.
   Also note what macOS reports while its question is unanswered (the installer
   expects "not determined" and keeps waiting; the doctor shows WARN).
4b. Variants, each from a fresh install unless said otherwise: don't answer for a
   minute → "macOS is still waiting for your answer", System Settings opens, Next
   steps start with "Allow notifications". Upgrade with Banners → only the hint, no
   System Settings. Upgrade with notifications off → System Settings opens.
   `HOOK_ME_UP_NO_ONBOARDING=1` → "Notification check skipped". `HOOK_ME_UP_VERSION=v0.1.2`
   → "Notification check skipped (this version's hook-me-up-setup has no notifications
   command)" and the install completes.
5. System Settings → Notifications → Hook Me Up: Allow notifications on, **style set
   to Alerts** (they stay on screen until you answer), sounds on. The log says
   `notifications: authorized, style alert`. Notifications show the app icon: a white
   spark on a clay rounded square.
6. The menu bar shows ✻ (with the number of waiting entries, ⏸ while paused).
7. The first click on a notification with Terminal, iTerm2 or Ghostty asks once for
   Automation permission: allow it.
8. `~/Applications/"Hook Me Up.app"/Contents/MacOS/hook-me-up-setup doctor`: every line
   PASS (Pause may be INFO; Editor extension is always INFO: "installed in VS Code", say,
   or, for an editor without it, the `--install-extension` command), exit status 0. Then, one at a time, and run the doctor after
   each (undo it afterwards): set the style to Banners (WARN, exit 0); turn notifications
   off (FAIL, exit 1, fix names System Settings); Pause for 30 minutes (INFO); quit from
   the menu (Agent process FAIL with `launchctl kickstart`; Agent FAIL). Before upgrading
   from 0.1.x, `make build && .build/release/hook-me-up-setup doctor` against the old agent
   says it is too old to answer status questions (Agent WARN, exit 0).

### Homebrew

1. `brew tap robertodf99/tap`, `brew trust --tap robertodf99/tap` (recent Homebrew
   refuses untrusted taps), then `brew install hook-me-up`: the caveats show the `hook-me-up-setup
   install --hook "…/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up"` command,
   `brew services start hook-me-up` and `hook-me-up-setup doctor`.
2. `xattr -r -p com.apple.quarantine "$(brew --prefix hook-me-up)/Hook Me Up.app"`
   prints nothing (not quarantined), and the agent starts with `brew services start`.
3. With the hooks added at the opt path, `hook-me-up-setup doctor` passes: App says
   "installed with Homebrew", LaunchAgent `sh.brew.hook-me-up starts this app`
   (`homebrew.mxcl.hook-me-up` before Homebrew 7), Agent process "running" (from
   `launchctl print gui/$(id -u)/sh.brew.hook-me-up`), Hooks name the opt path. A leftover
   `homebrew.mxcl.hook-me-up.plist` next to the `sh.brew` one is not a second
   installation. With the curl installer's copy installed too, it warns "Two
   installations" (and "Other installation" if both have hooks). Quit from the menu,
   then the doctor: Agent process FAIL with `brew services restart hook-me-up`.
4. `brew upgrade hook-me-up && brew services restart hook-me-up`: the doctor still
   passes (the hooks at the opt path follow the upgrade).

## 1. Requests

| # | Check | Expected |
|---|---|---|
| 1 | A command needs permission | Alert "project · Needs permission", body = plain-language title and description, warnings as text (e.g. "⚠︎ Leaves your machine"), the Hook Me Up icon, the default sound. Actions in this order: Approve (shown as the button), then Deny and, when offered, Approve for session (under "Options" on hover). No Open session action. |
| 2 | Approve; another time Deny | Approve runs it. Deny → Claude says "User denied this via a notification. Don't retry the same action; ask or try another approach." and does not retry the same thing. The notification goes away. |
| 3 | A request with a session suggestion → "Approve for session: Bash(…)" | Runs it; the same command is not asked again in this session; no settings file changes (check `ls -la .claude/` and the `~/.claude/settings.json` mtime). |
| 4 | Click the notification body (any kind: request, question, plan, finished, timed out) | The session's terminal comes forward (Terminal / iTerm2: the exact tab), the notification goes, the terminal dialog is there to answer. |
| 4b | Lock the screen (⌃⌘Q) while a request notification shows, then use Approve, Deny or Reply… from the lock screen | macOS asks you to unlock first; nothing reaches Claude until you do. |
| 5 | Question with one choice (AskUserQuestion) | "project · Question", one button per option (up to 4) plus Reply… for your own answer (a reply of "1" is sent as "1", not as the first option). More than 4 options: numbered in the body, Reply… is the only action and shows as the button (number, label or your own text). |
| 6 | Two questions, the second multi-select | "Question 1 of 2" → answer → "Question 2 of 2" appears (no second sound) with numbered options → Reply… "1, 3" → Claude reports both answers (multi-select joined with ", "). Reply "9" first → the question comes back with "⚠︎ Reply with option numbers, e.g. 1, 3" and nothing is sent. |
| 7 | Plan mode (`ExitPlanMode`): Approve plan; another time Request changes… with text; once with empty text | "project · Plan to approve", body = plan title and first lines. Approve → Claude leaves plan mode and proceeds. Request changes → Claude stays in plan mode and revises with your text. Empty text → the notification comes back, nothing sent. |
| 8 | Answer in the terminal while the notification shows | The notification disappears within a second; no second decision. |
| 9 | Clear the notification (Notification Center → Clear) without answering | Nothing is decided; the terminal dialog still works. |
| 10 | Wait 10 minutes on a request | At ~590 s it becomes "project · Timed out" (silent, "Answer in the terminal: …"); the terminal dialog still works; it goes away with the session's next prompt. |

## 2. Heads-ups

| # | Check | Expected |
|---|---|---|
| 11 | A session finishes a turn (`Stop`) | "project · Finished" with a one-line gist, default sound, no buttons; clicking it opens the session; replaced by that session's next entry; removed when you type a new prompt or the session ends. Headless runs (`claude -p`) send nothing. |
| 12 | MCP form (`elicitation_dialog`) | "project · Waiting for your reply"; removed by the next prompt. |
| 13 | Several projects at once, including two repositories with the same folder name and a worktree of one of them | Notifications grouped per repository (one stack each in Notification Center); the worktree joins its repository's stack; same-named repositories are not mixed. |

## 3. Fail-open

| # | Check | Expected |
|---|---|---|
| 14 | Notifications off for Hook Me Up in System Settings, trigger a prompt; another time turn them off while a request notification waits, then trigger another prompt | Terminal dialog at once; a request that was waiting is released to its terminal dialog too (at the next request, or within a minute); the log explains how to turn notifications on (once). Turn them on again → the next request is a notification (no relaunch needed). |
| 15 | Agent down: `launchctl bootout gui/$(id -u)/io.github.robertodf99.hook-me-up`, trigger a prompt | Terminal dialog at once. Then run the installer again (or `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.github.robertodf99.hook-me-up.plist`). |
| 16 | Agent killed mid-request (`pkill -9 HookMeUp`) | Terminal dialog usable at once, nothing denied; launchd restarts the agent. |
| 17 | Menu bar → Pause for 30 minutes, trigger a prompt; Resume | While paused: terminal dialog at once, no Finished/Waiting notifications. After Resume: normal. |
| 17b | With the agent running, `rm -rf ~/Library/Application\ Support/hook-me-up`, then trigger a prompt after ~5 s | Within about 5 s the log says `socket was removed or replaced; listening again`; the folder is back (`stat -f %Lp` says 700, the socket 600); the request is a notification; the doctor's Agent line passes. |

## 4. Terminals and sessions

| # | Check | Expected |
|---|---|---|
| 18 | Click a notification from Terminal, iTerm2, Ghostty, VS Code, Cursor, Claude desktop (and, if installed, VS Code Insiders, Windsurf, Zed) | Terminal / iTerm2: the exact tab is selected. VS Code / Cursor (and Insiders, Windsurf): the click focuses the open window that contains the session's folder, and opens no new window (with the editor extension, its terminal is shown too: 18e). Zed and the others: the app comes forward. The log says which strategy was used (`open session: focused an existing window of …` or `open session: no matching window or no window state; brought the editor forward …`) and the frontmost app, never a path. |
| 18d | Ghostty 1.3 or later: two windows (or tabs) in different folders, Claude Code in one; click its notification from the other window, then from another app | macOS asks once to let Hook Me Up control Ghostty (allow it); then the session's terminal comes to the front, in its window and tab (`open session: ghostty terminal focused`, frontmost `com.mitchellh.ghostty`). With `macos-applescript = false` in Ghostty's config (restart Ghostty), or Automation denied for Ghostty, or Ghostty before 1.3: Ghostty only comes to the front (`ghostty script failed`). Note whether Ghostty actually comes forward in each case (the frontmost line). Then, title marker: (a) two splits (or two tabs) in the same folder, Claude Code in either one, the other focused: the click focuses Claude Code's split (`open session: ghostty terminal focused (title marker)`); its title flickers and is back to what it was within 1.5 s (time it; no stray characters in the title or on screen). Repeat with Claude Code in the other split. (b) Add `title = fixed` to Ghostty's config (reload it): the click only brings Ghostty forward (`ghostty: title marker not seen (2)`), the title stays "fixed". (c) Ghostty's shell integration with and without its title feature (`shell-integration-features = no-title`): (a) works in both; note the title before and after. (d) Click an older notification from a session you have since ended (`/exit`), with the two splits still open: Ghostty only comes forward (`ghostty: no usable tty (2)`), and neither split's title changes. (e) Click a notification of a session that is busy (Claude Code animates a spinner in its title while it works): note whether its split is focused or the log says `title marker not seen (2)`, and that no marker is left in the title afterwards. Logs never show a tty, a title or the marker. |
| 18e | VS Code with the editor extension (installed by the installer; reload windows opened before): (a) one window with two integrated terminals (and a terminal in an editor tab), Claude Code in one, another terminal focused or the panel hidden; (b) two windows, Claude Code in a terminal of each; (c) the extension uninstalled (Extensions view) or (d) disabled; (e) VS Code Insiders, Cursor, Windsurf if installed | (a) The click focuses the window and shows Claude Code's terminal (panel opened if hidden), with the cursor in it; the log says `open session: asked com.microsoft.VSCode to show the session's terminal` then `focused an existing window`. (b) Each click shows the right terminal in the right window; the other window changes nothing. (c) Exactly as 18b (no "asked" line). (d) The window is focused as in 18b and no terminal changes ("asked" is still logged: a disabled extension can't be told from outside). (e) The same as (a) and (b), with that editor's bundle id. Also: run Claude Code in a folder outside every open window (18c's last case) in a window's terminal: the editor comes forward and, if that window is in front, its terminal is shown. `~/Library/Application Support/hook-me-up/editor-focus-request.json` holds only `created`, `nonce`, `pids`, `version` (`stat -f %Lp` says 600). |
| 18b | With two VS Code windows open (two projects), run Claude Code in each and click a notification from each | Each click focuses the open window that contains that session's folder, not just VS Code; no new window opens. Then close one of the two windows (its session ends) and click an older notification from it: VS Code only comes to the front, and no window opens. Close the last window too (VS Code keeps running) and click again: VS Code only comes to the front. |
| 18c | In VS Code, open a repository as the window and run Claude Code in a worktree inside it (`.worktrees/<name>` or `.claude/worktrees/<name>`), then in a subfolder of it; open a saved multi-root `.code-workspace` and run Claude Code in one of its folders; last, `cd` to a folder outside every open window and run Claude Code there | The click focuses the open window that contains the session's folder (the repository's window, or the workspace's window), and opens no new window. For the outside folder VS Code only comes to the front (`no matching window or no window state; brought the editor forward`). |
| 19 | Subagent permission request | Title ends with "· subagent". |
| 20 | Your usual permission mode (e.g. auto) for a while | Note which tool names reach the notifications. |

## 5. Uninstall and reboot

| # | Check | Expected |
|---|---|---|
| 21 | The uninstall one-liner (or `make uninstall`) | Shows the diff (only our five hook entries removed), asks, backs up, writes; LaunchAgent removed, the app and `~/Library/Application Support/hook-me-up` removed, backups kept; "Removed the Hook Me Up extension from VS Code." (and each other editor that had it), and `code --list-extensions` no longer lists it. Other hooks and keys untouched. With Homebrew's copy installed too: the folder (and Homebrew's agent's socket) and the editor extension stay, the uninstaller says "Kept …: Homebrew's copy of Hook Me Up uses it." (and that it kept the extension), and `sh.brew.hook-me-up` (or `homebrew.mxcl.hook-me-up`) still runs and passes the doctor. |
| 22 | Reinstall, reboot | The agent starts at login (✻ in the menu bar); notifications work without opening anything. |
