# Click to focus and notification interactions

## Claude Code notifications

| When Claude Code… | Notification | Actions, in order |
|---|---|---|
| needs permission for a tool | `project · Needs permission`, with a plain-language summary and warnings such as "⚠︎ Leaves your machine" | Approve, Deny, Approve for session (when Claude Code suggests a session rule) |
| asks a question with up to four options | `project · Question` | One action per option, then Reply… for your own answer |
| asks a question with more options, or a multi-select one | `project · Question`, the options numbered in the body | Reply…: type `2`, `1, 3`, or an option's label |
| wants a plan approved | `project · Plan to approve`, with the first lines of the plan | Approve plan, Request changes… (your text goes back to Claude) |
| finishes a turn, or waits for a reply | `project · Finished` / `Waiting for your reply` | none |

## Clicking and answering

- **Clicking a notification opens its session**: Terminal and iTerm2 select the exact
  tab. Ghostty (1.3 or later) focuses the terminal whose working directory is the folder
  Claude Code was started in. When several terminals are there (splits or tabs in the
  same folder), Hook Me Up briefly sets the title of the session's own terminal to a
  random marker, asks Ghostty which terminal shows it, puts the old title back and
  focuses that terminal; the title is back within about a second. When Ghostty doesn't
  show the marker in time (a fixed `title = …` in its config, or the session changed its
  title first), the title is cleared instead, so no marker is left behind (a title the
  session set meanwhile shows again when it next sets one), and Ghostty just comes to
  the front, as it does when the session has ended, when no terminal is in the folder, or
  when Ghostty's AppleScript is off (`macos-applescript = false`).
  VS Code and Cursor (and VS Code Insiders and Windsurf) focus the open window that
  contains the folder Claude Code was started in: that folder's window, the window of
  the repository a worktree or subfolder belongs to, or a saved `.code-workspace` that
  includes it; with the [editor extension](#editor-extension), the session's integrated
  terminal is shown too, even when the window has several. While the session's window is
  open, a click opens no new window; when no open window contains the folder, the editor
  just comes to the front (and, with the extension, the front window shows the session's
  terminal if it has it). The editor keeps its list of windows up to date with a delay,
  so right after you close windows a click may just bring the editor to the front. Zed and
  other apps come to the front.
  The click hands the request to Claude Code's terminal dialog: nothing is
  approved or answered from it. In a multi-question flow, the answers given so far are
  dropped and the terminal asks all the questions again.
- macOS shows the **first action as a button** and the others under **Options** when
  you hover the notification, so the most likely answer comes first.
- Several questions arrive one at a time; Claude gets all the answers after the last.
  A reply that can't be understood brings the question back with a hint.
- Answering needs an unlocked Mac, so nothing can be approved from the lock screen.
- Notifications are grouped per repository, play the default sound once, and
  disappear when the request is answered here, cancelled, or the session moves on. A
  request you answer in the terminal goes away when the session finishes its turn or
  you send the next prompt, not at once.

The hook-shaped menu-bar item shows how many requests are waiting and offers
**Pause for 30 minutes**, **Resume** and **Quit**.

## Editor extension

VS Code can't be asked from outside which integrated terminal runs a session, so Hook Me
Up comes with a small extension for VS Code, VS Code Insiders, Cursor and Windsurf (plain
JavaScript, no dependencies; source in [editor-extension/](../editor-extension/)). On a
click, the agent writes a request to
`~/Library/Application Support/hook-me-up/editor-focus-request.json`: a random id, the
time and the session's process ids, nothing else (no paths, titles or commands). Every
editor window watches that file; the window with a terminal whose process is one of those
ids shows it, and the others do nothing. Without the extension (or with it disabled), a
click works exactly as before: it focuses the window.

- The installer adds it with each editor's command-line tool (`code`, `code-insiders`,
  `cursor`, `windsurf`, on your `PATH` or inside the app in `/Applications` or
  `~/Applications`) and says so; if adding it fails, the install goes on. Set
  `HOOK_ME_UP_NO_EDITOR_EXTENSION=1` to skip it.
- Windows that were already open may need a reload (**Developer: Reload Window**) before
  the extension runs in them.
- The uninstaller removes it. You can also remove it from the editor's Extensions view
  (it is "Hook Me Up", id `hook-me-up.hook-me-up`).
- `hook-me-up-setup doctor` shows which editors have it (an INFO line; it never fails).
- Profiles: Hook Me Up checks the extension in the default profile's list (where the
  installer adds it). A window that uses another profile runs it only if that profile has
  it too; otherwise the click focuses that window as before.
