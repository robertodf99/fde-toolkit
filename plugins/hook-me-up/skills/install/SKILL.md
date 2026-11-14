---
name: install
description: Install or upgrade Hook Me Up, which answers Claude Code from native macOS notifications. Runs the official installer, shows the changes it would make to ~/.claude/settings.json and adds the hooks only after the user confirms in chat.
disable-model-invocation: true
---

# Install Hook Me Up

Hook Me Up shows Claude Code's permission requests, questions and plan approvals as
native macOS notifications you can answer. It needs three things: the app in
`~/Applications`, a LaunchAgent that starts it at login, and five hooks in
`~/.claude/settings.json`. The installer does the first two at once and the hooks only
with the user's consent. Your job is to get that consent here in the chat.

Never add the hooks without an explicit yes from the user in this conversation, and
never edit `~/.claude/settings.json` yourself: the installer's own command does it,
with a backup.

## Steps

1. Check this is macOS 14 or later: `uname -s` must print `Darwin` and
   `sw_vers -productVersion` must be 14 or higher. Otherwise stop and say Hook Me Up
   runs on macOS 14 or later only.

   Then check for a Homebrew copy: if `command -v brew` finds Homebrew, run
   `brew list --versions hook-me-up`. If it prints a version, Hook Me Up is already
   installed with Homebrew. Say so, and that two copies can't run side by side (only
   one agent runs, and two sets of hooks notify twice). Offer the Homebrew way instead
   (`brew upgrade hook-me-up && brew services restart hook-me-up`, then
   `/hook-me-up:doctor`), and stop unless the user explicitly wants to switch to the
   installer after removing the Homebrew copy. The installer refuses to run next to it
   anyway, unless `HOOK_ME_UP_IGNORE_HOMEBREW=1` is set; don't set that on your own.

2. Run the installer without a terminal, so it changes nothing in the settings and
   prints what it would change instead:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/install.sh | HOOK_ME_UP_NO_TTY=1 bash
   ```

   It downloads the latest release, checks its SHA-256, installs
   `~/Applications/Hook Me Up.app`, starts the agent, and spends up to 10 seconds on a
   notification check (macOS may ask the user to allow notifications from Hook Me Up
   meanwhile). Don't add `HOOK_ME_UP_YES=1`.

3. Read the output:
   - `No changes: … is already set up`: the hooks are already there (an upgrade).
     Skip to step 6.
   - `Claude Code was not found (~/.claude is missing)`: the app is installed, but
     there is nothing to add the hooks to. Say so, and that running this again after
     installing Claude Code adds them. Skip to step 6.
   - Otherwise it prints `Exact text changes to …settings.json` with a diff, and then
     `No terminal to ask, so ~/.claude/settings.json was not changed. To add the hooks,
     run:` followed by one command line.
   - `already installed with Homebrew`: see step 1; stop.
   - If it failed (a checksum mismatch, no network, an unexpected settings shape),
     show the error and stop.

4. Show the user the diff exactly as printed, in a code block, and explain it in one
   or two sentences: only a `hooks` block with five Hook Me Up entries is added
   (PermissionRequest, Notification, Stop, UserPromptSubmit, SessionEnd); every other
   key and hook stays; a timestamped backup is written next to the file first. Mention
   any `Warning:` lines it printed (for example hooks of another Hook Me Up copy, which
   would notify twice). Then ask whether to add the hooks, and wait for the answer.

5. Only if the user says yes: run the exact command the installer printed after `To add
   the hooks, run:`, with ` --yes` appended. Don't change its paths. Report the
   `Wrote …` line and the backup path. If it says the file changed while it was
   running, run step 2 again. If the user says no, say that nothing was changed and
   how to do it later (this command, or the installer in a terminal).

6. Finish with what is left to do, from the installer's `Next steps` and notification
   check output: allow notifications for Hook Me Up when macOS asks, set their style
   to Alerts in System Settings > Notifications > Hook Me Up so requests stay on
   screen, and restart the Claude Code sessions that are already running, this one
   included, so they load the hooks. Suggest `/hook-me-up:doctor` to check
   everything afterwards.
