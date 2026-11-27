# Configuration

Both scripts include Codex by default when its profile exists. Use `--no-codex`
to exclude it. The legacy `--codex` flag is accepted as a no-op; it does not override
`--no-codex` if both are supplied.

The installer and uninstaller read these environment variables:

| Variable | Effect |
|---|---|
| `CODEX_HOME=<folder>` | Codex profile folder (default `~/.codex`); install skips it if absent |
| `HOOK_ME_UP_VERSION=1.2.3` | Install that version from its `hook-me-up-v*` tag (also accepts `hook-me-up-v1.2.3`) |
| `HOOK_ME_UP_YES=1` | Accept both clients’ hook diffs without asking (non-interactive installs and uninstalls) |
| `HOOK_ME_UP_ZIP=<path>` | Install a local package (its `.sha256` must sit next to it) |
| `HOOK_ME_UP_NO_ONBOARDING=1` | Skip the notification check after starting the agent (no waiting, no test notification, System Settings stays closed) |
| `HOOK_ME_UP_NO_EDITOR_EXTENSION=1` | Don't add the [editor extension](CLICK-TO-FOCUS.md#editor-extension) to VS Code, VS Code Insiders, Cursor or Windsurf |

Example:

```sh
curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/tools/hook-me-up/install.sh | HOOK_ME_UP_YES=1 bash
```

Without a terminal and without `HOOK_ME_UP_YES=1`, the installer changes nothing in
your settings and prints the command to run.

To take a break, use **Pause for 30 minutes** in the menu bar: requests go to the
terminal until it ends or you choose **Resume**.

## Installation details

The installer downloads the latest release (and checks its SHA-256), installs
`~/Applications/Hook Me Up.app`, shows the changes it would make to
`~/.claude/settings.json` and `$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`)
and **asks before writing them** (with a timestamped backup), adds the [editor
extension](CLICK-TO-FOCUS.md#editor-extension) to VS Code, VS Code Insiders, Cursor and
Windsurf when it finds their command-line tool, and starts the menu-bar agent at login.
Run it again to upgrade.

### Install from Claude Code

Hook Me Up is also a Claude Code plugin with three commands that run the same installer
and ask for your confirmation in the chat:

```text
/plugin marketplace add robertodf99/fde-toolkit
/plugin install hook-me-up@fde-toolkit
```

(On Claude Code 2.1.275 or later, `/plugin install hook-me-up --marketplace robertodf99/fde-toolkit`
does both in one step.) Then:

- `/hook-me-up:install` installs or upgrades Hook Me Up: it shows the changes to
  both clients’ hook files and adds the hooks only after you say yes.
- `/hook-me-up:doctor` checks the installation and explains how to fix what is off.
- `/hook-me-up:uninstall` shows what would be removed and removes it after you say yes.

The plugin has commands only, no hooks: the hooks live in the clients’ user hook files,
as with the installer. Hooks inside the plugin would run in addition to those, and every
request would be notified twice.

### First run

Once the agent runs, the installer waits (up to a minute in a terminal, 10 seconds
without one) for you to answer macOS's question about notifications, shows a test
notification, and tells you what is left to do:

1. Allow notifications for **Hook Me Up** when macOS asks (or in System Settings →
   Notifications → Hook Me Up).
2. In the same place, set the style to **Alerts**, so requests stay on screen until
   you answer them. On a first install, the installer opens System Settings at
   Notifications when the style isn't Alerts yet; on an upgrade, only when
   notifications are off.
3. Restart CLI sessions that were already running, so they load the hooks, and
   review and approve `/hooks` in Codex.

## Uninstall details

The [uninstaller](../README.md#uninstall) shows both clients’ hook diffs and asks
before writing, with a backup beside each file. It stops the agent and removes
Hook Me Up's hooks, the app, its support folder and the editor extension (with each
editor's command-line tool it finds). Settings backups and the log stay in place.
With `--no-codex`, Codex hooks stay intact; if they still call the app, the app and
agent stay installed too, with a warning. Rerun without `--no-codex` to finish.
