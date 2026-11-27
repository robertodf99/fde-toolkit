# Troubleshooting

Start with the doctor. It checks the app, the LaunchAgent, the running agent, the hooks
in `~/.claude/settings.json`, the Codex hook file and the notification settings, and
says how to fix each problem (it changes nothing itself):

```sh
~/Applications/"Hook Me Up.app"/Contents/MacOS/hook-me-up-setup doctor
```

From Claude Code, run `/hook-me-up:doctor`.

The agent writes its log to `~/Library/Logs/hook-me-up.log`.

- **No notifications.** Check System Settings → Notifications → Hook Me Up. While
  notifications are off, every request goes to the terminal and the log says how to
  turn them on.
- **Nothing happens at all.** Make sure the agent runs (the hook icon in the menu bar;
  else run the installer again) and restart your CLI sessions so they load the hooks. For Codex, review
  and approve `/hooks`; see [Codex diagnostics](CODEX.md).
- **The agent's folder was deleted** (`~/Library/Application Support/hook-me-up`, say by
  a cleanup tool): the agent notices within about 5 seconds, creates it again and keeps
  listening (the log says `socket was removed or replaced; listening again`). Requests in
  between go to the terminal.
- **The icon is out of date** after an upgrade. macOS caches it:

  ```sh
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Hook Me Up.app"
  killall NotificationCenter usernoted
  ```

  If it is still stale, log out and back in.
- **Login Items shows "unidentified developer".** Releases are signed ad-hoc; keep the
  item enabled. See [Why macOS says "unidentified developer"](SECURITY.md#why-macos-says-unidentified-developer)
  for what that means and how to check what you installed.
- **Clicking a notification doesn't select the tab.** The first time, macOS asks to let
  Hook Me Up control Terminal, iTerm2 or Ghostty; allow it in System Settings → Privacy &
  Security → Automation. With several Ghostty terminals in the session's folder, the log
  says why one wasn't picked (`ghostty: title marker not seen`, for instance when
  Ghostty's config sets `title`). In VS Code and the editors built on it, the terminal is
  shown only with the [editor extension](CLICK-TO-FOCUS.md#editor-extension): check it with the doctor, and
  reload windows opened before it was installed.
