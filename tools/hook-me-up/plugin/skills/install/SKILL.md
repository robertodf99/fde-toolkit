---
name: install
description: Install or upgrade Hook Me Up, which answers Claude Code and Codex CLI from native macOS notifications. Runs the official installer, shows the changes it would make to both clients’ hook files and adds the hooks only after the user confirms in chat.
disable-model-invocation: true
---

# Install Hook Me Up

Hook Me Up shows Claude Code's permission requests, questions and plan approvals as
native macOS notifications you can answer. Codex CLI supports permission requests and
finished notifications too. It needs three things: the app in `~/Applications`, a
LaunchAgent that starts it at login, and five hooks in `~/.claude/settings.json`, plus
five Codex hooks in `$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`) when that
profile exists. The installer does the first two at once and the hooks only with the
user's consent. Your job is to get that consent here in the chat.

Never add the hooks without an explicit yes from the user in this conversation, and
never edit `~/.claude/settings.json` yourself: the installer's own command does it,
with a backup.

Codex CLI hooks are included by default when `$CODEX_HOME` (default `~/.codex`)
exists. Apply the same diff and consent steps to both clients. If the user asks to
exclude Codex, use `bash -s -- --no-codex` in both the preview and confirmed
installer/uninstaller commands. Never edit either client's hook files or Codex's
`config.toml` / trust state by hand. After installing Codex hooks, remind the user
to review and approve `/hooks` in Codex.

## Steps

1. Check this is macOS 14 or later: `uname -s` must print `Darwin` and
   `sw_vers -productVersion` must be 14 or higher. Otherwise stop and say Hook Me Up
   runs on macOS 14 or later only.

2. Run the installer without a terminal, so it changes nothing in the settings and
   prints what it would change instead:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | HOOK_ME_UP_NO_TTY=1 bash
   ```

   It downloads the latest release, checks its SHA-256, installs
   `~/Applications/Hook Me Up.app`, adds Hook Me Up's editor extension to VS Code,
   VS Code Insiders, Cursor and Windsurf when it finds their command-line tool (so a click
   also shows the session's integrated terminal; `HOOK_ME_UP_NO_EDITOR_EXTENSION=1`
   skips that, if the user asks), starts the agent, and spends up to 10 seconds on a
   notification check (macOS may ask the user to allow notifications from Hook Me Up
   meanwhile). Don't add `HOOK_ME_UP_YES=1`.

3. Read the output for **each client** before deciding what is left:
   - `No changes: … is already set up`: that client's hooks are already there.
   - Missing `~/.claude` or Codex profile: that client is skipped. Run the installer
     again after installing the CLI to add its hooks. Do not skip the other client's
     diff because one is already set up or absent.
   - Otherwise it prints `Exact text changes to …settings.json` or `…hooks.json`,
     followed by the diff and a message saying that file was not changed.
   - If it failed (a checksum mismatch, no network, an unexpected settings shape),
     show the error and stop.

4. Show every applicable diff exactly as printed in a code block, including each
   client's "No changes" or skipped result. Explain that only Hook Me Up entries are
   added: Claude's PermissionRequest, Notification, Stop, UserPromptSubmit, SessionEnd;
   Codex's PermissionRequest, Stop, UserPromptSubmit, SessionEnd, Interrupt. Every other
   key and hook stays; each changed file gets a timestamped backup beside it. Mention
   any `Warning:` lines (for example another Hook Me Up copy that would notify twice).
   If there are pending changes, ask whether to add those hooks and wait for the answer.
   If neither client needs changes, continue to step 6.

5. Only if the user says yes: rerun the same installer with `HOOK_ME_UP_YES=1` and
   `HOOK_ME_UP_NO_TTY=1`, retaining `--no-codex` if selected in the preview:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | HOOK_ME_UP_YES=1 HOOK_ME_UP_NO_TTY=1 bash
   ```

   Report each `Wrote …` line and backup path. If it says a file changed while it
   was running, return to step 2. If the user says no, say that the hook files were
   not changed and how to do it later (the installer in a terminal).

6. Finish with what is left to do, from the installer's `Next steps` and notification
   check output: allow notifications for Hook Me Up when macOS asks, set their style
   to Alerts in System Settings > Notifications > Hook Me Up so requests stay on
   screen, review and approve `/hooks` in Codex, and restart CLI sessions already
   running, this one included, so they load the hooks. If it added the editor extension, also mention
   reloading editor windows that were already open. Suggest `/hook-me-up:doctor` to check
   everything afterwards.
