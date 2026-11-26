---
name: doctor
description: Check a Hook Me Up installation (the app, its LaunchAgent, the running agent, the hooks in ~/.claude/settings.json and the macOS notification settings) and explain how to fix what is off.
disable-model-invocation: true
---

# Check Hook Me Up

`hook-me-up-setup doctor` checks everything Hook Me Up needs and prints one line per
check: `PASS`, `WARN`, `FAIL`, `SKIP` or `INFO`, with a `Fix:` under each problem. It
changes nothing. It exits 1 when a check failed; warnings don't.

## Steps

1. Find `hook-me-up-setup` where the installer puts it:
   `~/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup`. If it doesn't
   exist, Hook Me Up isn't installed: suggest `/hook-me-up:install` and stop.

2. Run it: `"<path>" doctor`. A non-zero exit status is expected when something
   fails; read the output either way. If it prints a usage message instead of the
   checks, that copy is older than the doctor (before 0.2.0): suggest
   `/hook-me-up:install` to upgrade, then run this again.

3. Explain the result in plain words, problems first: each `FAIL`, then each `WARN`,
   with the fix it printed. Say briefly that everything else passed. Typical cases:
   - **Hooks** missing: `/hook-me-up:install` adds them after showing the changes.
   - **Notifications** off, or **Notification style** not Alerts: the user changes it
     in System Settings > Notifications > Hook Me Up (the fix line has a command
     that opens it).
   - **Agent** not running or too old: the fix restarts it (re-running the installer).
   - **Other installation**: another copy of Hook Me Up (an older one, for example)
     also has hooks in the settings, so requests are notified twice. Keep one.

4. Offer to run a fix only when it is a command and it doesn't change the settings
   file or remove anything (for example `launchctl kickstart …` or opening System
   Settings). For anything that edits `~/.claude/settings.json` or uninstalls, show
   the command and let the user decide; run it only after an explicit yes. After a
   fix, run the doctor again to confirm.

5. If hooks were added or changed, remind the user to restart the Claude Code sessions
   that are already running, this one included.
