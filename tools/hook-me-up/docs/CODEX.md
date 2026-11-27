# Codex CLI

Codex hooks are installed alongside Claude Code by default when `$CODEX_HOME`
(default `~/.codex`) exists. Use the normal [installer](../README.md#install);
append `bash -s -- --no-codex` instead of `bash` to exclude Codex.

The installer shows a separate diff for `$CODEX_HOME/hooks.json` (default
`~/.codex/hooks.json`), asks before writing it, backs it up and writes atomically.
It skips Codex if that profile folder doesn't exist, and never needs the Codex binary
on PATH. An older package without `--client` support skips Codex and tells you to
upgrade. With `--no-codex`, installation leaves all Codex files untouched and
prints no Codex output.

After installation, **review and approve the hooks with `/hooks` in Codex**. Until
trusted, they don't run. Hook Me Up never writes Codex's `config.toml`, `trusted_hash`
or trust state. Changing the hook command or moving its groups may require another
review in `/hooks`. Project hooks and hook definitions in `config.toml` are outside
this installer's scope.

| Codex event | What Hook Me Up does | Handler timeout |
|---|---|---|
| PermissionRequest | Approve or Deny from `project · Codex · Needs permission` | 600 s |
| Stop | `project · Codex · Finished`, with a gist of `last_assistant_message` when present | 10 s |
| UserPromptSubmit | Clear the session's notifications | 10 s |
| SessionEnd, Interrupt | Clear the session's notifications | 3 s |

**Codex waits for the hook before showing its approval dialog.** While a notification
waits, the terminal shows “Answer in the notification, or click it to answer here”.
Click the notification to focus the session and release the hook so Codex can show
its own dialog, or answer Approve / Deny in the notification. If nobody responds, the
hook returns without a decision after about 590 s. An unavailable agent, pause,
notifications off or a hook failure also returns without a decision; Codex then shows
its usual dialog. A managed policy may still require approval after an Allow.

Codex supports no “Approve for session”, question answers, plan approval or “Waiting
for your reply” notifications here. Its decisions contain only allow or deny (and a
message for deny). `apply_patch` summaries list paths from patch headers, warning on
writes outside the project. `codex exec` isn't distinguished in v1 and may show
“Finished”. This integration covers the CLI, not the Codex desktop app.

To remove both clients' hooks and the app:

```sh
curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/uninstall.sh | bash
```

With `--no-codex`, the uninstaller leaves Codex hooks untouched; if they still call
this app, it warns and keeps the app and agent installed. Backups remain beside each
client's hook file. `HOOK_ME_UP_YES=1` accepts both clients' diffs without prompting.

The doctor checks Codex hooks automatically, including duplicate handlers, the app
path, `[features] hooks = false` and a conflicting `[hooks]` table. Its trust line
is informational: review `/hooks` yourself. With no Hook Me Up hooks for Codex it
prints `INFO  Codex: not set up`. `doctor --home <folder>` isolates both clients;
`--codex-hooks <path>` checks another hooks file. The TOML checks cover standard table
syntax; they are text checks, not a full TOML parser or a query of effective policy.
