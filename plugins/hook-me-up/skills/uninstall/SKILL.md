---
name: uninstall
description: Uninstall Hook Me Up. Shows the changes to ~/.claude/settings.json (only its hooks removed) and removes the hooks, the agent and the app only after the user confirms in chat.
disable-model-invocation: true
---

# Uninstall Hook Me Up

The uninstaller removes Hook Me Up's hooks from `~/.claude/settings.json` first (after
a backup), and only then stops the agent and removes the app, its LaunchAgent, its
support folder and its editor extension from VS Code, VS Code Insiders, Cursor and
Windsurf (the folder and the extension are kept when Homebrew's copy of Hook Me Up is
installed too, which uses them). Settings backups stay. Your job is to get the user's consent here in the chat.

Never remove anything without an explicit yes from the user in this conversation, and
never edit `~/.claude/settings.json` yourself.

## Steps

1. Run the uninstaller without a terminal, so it changes nothing and prints what it
   would change:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/uninstall.sh | HOOK_ME_UP_NO_TTY=1 bash
   ```

2. Read the output:
   - `No changes: … is already free of Hook Me Up's hooks`, or no settings file: there
     are no hooks to remove, but with the user's yes step 4 still removes the app, its
     agent and its support folder (see step 3 for when the folder stays).
   - Otherwise it prints the diff of the settings file, then says the settings were not
     changed and that Hook Me Up keeps running.
   - `hook-me-up-setup is missing`: the app is already gone; say which entries to
     remove from the settings by hand (those whose command runs
     `…/Hook Me Up.app/Contents/MacOS/hook-me-up`) and stop.

3. Show the user the diff exactly as printed, in a code block: only Hook Me Up's
   hook entries are removed, every other key and hook stays, and a backup is written
   first. Say that the app and its LaunchAgent are removed too, and
   `~/Library/Application Support/hook-me-up` and the editor extension unless Homebrew's
   copy of Hook Me Up is installed too (it uses them, so the uninstaller keeps them and
   says so; Homebrew's copy and its service are left alone). Ask whether to go ahead, and wait for the
   answer.

4. Only if the user says yes, run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/uninstall.sh | HOOK_ME_UP_YES=1 HOOK_ME_UP_NO_TTY=1 bash
   ```

   and report what it says it removed and where the backups are. If the user says no,
   say that nothing was changed.

5. If Hook Me Up was installed with Homebrew instead (`brew list hook-me-up`
   succeeds), use Homebrew's copy, and ask before each step:
   1. Show the diff of
      `hook-me-up-setup uninstall --hook "$(brew --prefix)/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up" --dry-run`
      and, after a yes, run the same command with `--yes` instead of `--dry-run`.
   2. `brew services stop hook-me-up`, then `brew uninstall hook-me-up`.

6. Remind the user to restart the Claude Code sessions that are already running, this
   one included, so they stop calling the removed hooks. The plugin itself stays until
   they remove it with `/plugin`.
