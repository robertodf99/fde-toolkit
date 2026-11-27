# Hook Me Up

<p align="center"><img src="docs/images/logo.png" width="128" alt="Hook Me Up logo"></p>

Answer Claude Code and Codex CLI from native macOS notifications: approve or deny
requests, see when a turn finishes, and click to open its session. Claude Code also
supports questions and plan approvals. Built on each CLI's hooks, Hook Me Up fails
open: if anything is off, the CLI shows its usual terminal dialog.

![Answer Claude Code from a macOS notification and click to jump to its session](docs/images/demo.gif)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | bash
```

Requires macOS 14 or later and [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
or Codex CLI 0.172 or later. The installer checks the download, installs the app in
`~/Applications`, shows each client's hook diff and asks before writing, with backups.
It starts at login; run the installer again to upgrade.

Codex is included when `$CODEX_HOME` (default `~/.codex`) exists. To exclude it,
replace `bash` above with `bash -s -- --no-codex`. **Review and approve `/hooks` in
Codex** before its hooks can run. See [Codex details](docs/CODEX.md).

Or install the Claude Code plugin and run `/hook-me-up:install`:

```text
/plugin marketplace add robertodf99/fde-toolkit
/plugin install hook-me-up@fde-toolkit
```

The plugin uses the same installer and asks in chat. See [configuration and install
details](docs/CONFIGURATION.md) for plugin commands, environment variables and backups.

## First run

1. Allow notifications for **Hook Me Up** when macOS asks, or in System Settings →
   Notifications → Hook Me Up. The installer sends a test notification.
2. Set the notification style to **Alerts** so requests stay on screen until answered.
3. Restart CLI sessions that were already running; approve `/hooks` in Codex. Reload
   existing VS Code / Cursor windows to enable the installed editor extension.

## What you'll see

| When Claude Code… | Notification | Actions |
|---|---|---|
| needs tool permission | `project · Needs permission`, with a summary and warnings | Approve, Deny, Approve for session (when suggested) |
| asks a question with up to four options | `project · Question` | An action per option, Reply… for your own answer |
| asks a longer or multi-select question | `project · Question`, numbered options | Reply… with `2`, `1, 3`, or an option's label |
| wants a plan approved | `project · Plan to approve`, with its first lines | Approve plan, Request changes… |
| finishes or waits for a reply | `project · Finished` / `Waiting for your reply` | Click to open the session |

| When Codex CLI… | Notification | Actions |
|---|---|---|
| needs tool permission | `project · Codex · Needs permission` | Approve, Deny, click to answer in the terminal |
| finishes a turn | `project · Codex · Finished` | Click to open the session |

Codex waits for the hook before showing its dialog; a click or timeout releases it.
No session approvals, question answers or plan approvals; `codex exec` may show Finished.
Events, timeouts, trust and other limitations: [Codex CLI](docs/CODEX.md).

Clicking focuses the session's terminal or editor window; the included extension
also selects its integrated terminal in VS Code, VS Code Insiders, Cursor and Windsurf.
See [click to focus and notification interactions](docs/CLICK-TO-FOCUS.md) for Ghostty,
editor profiles, multi-question replies and action placement. Answering requires an
unlocked Mac. The menu bar offers **Pause for 30 minutes**, **Resume** and **Quit**.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/uninstall.sh | bash
```

Shows both clients' hook diffs, asks, then removes the hooks, app, agent and editor
extension. Backups stay. Use `bash -s -- --no-codex` to keep Codex hooks; the app stays
too if they still call it. See [uninstall details](docs/CONFIGURATION.md#uninstall-details).

## Troubleshooting

Run the doctor (or `/hook-me-up:doctor` in Claude Code):

```sh
~/Applications/"Hook Me Up.app"/Contents/MacOS/hook-me-up-setup doctor
```

Log: `~/Library/Logs/hook-me-up.log`.

- **No notifications:** enable them in System Settings → Notifications → Hook Me Up.
- **Nothing happens:** check the menu-bar agent, restart CLI sessions and approve
  `/hooks` in Codex. Rerun the installer if the agent is missing.
- **A click doesn't select the tab:** allow Automation in System Settings → Privacy &
  Security; reload editor windows. See [focus help](docs/CLICK-TO-FOCUS.md).
- **“Unidentified developer”:** releases are signed ad-hoc. Keep the Login Items entry
  enabled; see [security and verifying a release](docs/SECURITY.md).

More fixes: [troubleshooting](docs/TROUBLESHOOTING.md). For source builds and the
architecture, see [development](docs/DEVELOPMENT.md) and [architecture](docs/ARCHITECTURE.md).

## Feedback

Tell me what worked and what broke in
[Feedback & ideas](https://github.com/robertodf99/fde-toolkit/discussions/1); questions go to
[Q&A](https://github.com/robertodf99/fde-toolkit/discussions/categories/q-a). For a bug,
[open an issue](https://github.com/robertodf99/fde-toolkit/issues/new/choose) with the
output of `hook-me-up-setup doctor`.

## Credits / License

Original blue/teal hook artwork; notification symbols identify Claude or Codex
([sources and licences](THIRD_PARTY_NOTICES.md)). The GIF shows the previous visual
identity and needs new screen recordings. Claude is a trademark of Anthropic;
Codex and OpenAI are trademarks of OpenAI. Hook Me Up is not affiliated with or
endorsed by either company. [MIT](../../LICENSE).
