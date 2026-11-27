# Set up FDE Toolkit

Tell your agent: **“Follow https://github.com/robertodf99/fde-toolkit/blob/main/INSTALL.md”.**

**Agent rules:** ask before installing software or changing user configuration;
show proposed changes first. Never read, paste or use credentials, buy a plan,
or change global settings silently. Let the user handle sign-in. Stop and report
failed steps; preserve existing files and approvals. Every command block is
self-contained. If using another stable checkout path, replace `~/fde-toolkit`
in every command below; never use `/tmp` or a worktree for methodology symlinks.

1. **Check the two bootstrap tools:** `git --version && python3 --version`
   (Python 3.9+). If missing, ask before installing [Git](https://git-scm.com/downloads/)
   or [Python](https://www.python.org/downloads/).

2. **Clone or update.** For an existing folder, check origin and local changes
   before pulling; stop if it is another repo, a worktree or has changes:

   ```sh
   if [ -e "$HOME/fde-toolkit" ]; then
     [ -d "$HOME/fde-toolkit/.git" ] || { printf 'Not a regular clone\n'; exit 1; }
     origin=$(git -C "$HOME/fde-toolkit" remote get-url origin) || exit 1
     case "$origin" in
       https://github.com/robertodf99/fde-toolkit|https://github.com/robertodf99/fde-toolkit.git) ;;
       *) printf 'Different origin; stop and report\n'; exit 1 ;;
     esac
     changes=$(git -C "$HOME/fde-toolkit" status --short) || exit 1
     [ -z "$changes" ] || { printf 'Local changes; stop and report\n'; exit 1; }
     git -C "$HOME/fde-toolkit" pull --ff-only
   else
     git clone https://github.com/robertodf99/fde-toolkit "$HOME/fde-toolkit"
   fi
   ```

   Run `bash "$HOME/fde-toolkit/scripts/check-setup.sh"` for the full inventory
   (✗ is expected before setup). Ask before installing missing components from
   [Claude Code](https://code.claude.com/docs/en/setup),
   [Codex CLI](https://developers.openai.com/codex/cli), [Herdr Desktop + Core](https://herdr.dev/download/)
   or [jq](https://jqlang.org/download/). Install/enable [Superpowers](https://github.com/obra/superpowers#installation)
   in both runtimes: Claude `/plugin install superpowers@claude-plugins-official`;
   Codex `/plugins` → search Superpowers → Install Plugin (agent menus, not shell).
   [gh](https://cli.github.com/) is optional. Hook Me Up needs macOS 14+
   (`sw_vers -productVersion`); on Linux skip it.

3. **Hook Me Up, after permission to install the app.** Preview the hooks without
   `/dev/tty` prompts, clearing any inherited auto-yes flag:

   ```sh
   env -u HOOK_ME_UP_YES HOOK_ME_UP_NO_TTY=1 bash "$HOME/fde-toolkit/tools/hook-me-up/install.sh"
   ```

   This installs the app, login agent and editor extension but leaves both clients'
   hook settings alone. Show the previews for `~/.claude/settings.json` and
   `$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`), including each diff,
   "No changes" result or missing-profile notice. **Only after explicit yes for the
   displayed changes**, run:

   ```sh
   HOOK_ME_UP_YES=1 HOOK_ME_UP_NO_TTY=1 bash "$HOME/fde-toolkit/tools/hook-me-up/install.sh"
   ```

   If the user excludes Codex, append `--no-codex` to **both** the preview and
   confirmed commands; only Claude's hook changes then need approval. Keep the same
   `CODEX_HOME` for both runs. Allow notifications, choose **Alerts**, review and
   approve `/hooks` in Codex if its hooks were added, and restart existing sessions
   of **both Claude Code and Codex CLI** so they load the hooks. Then run
   `"$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup" doctor`.
   [First-run details](tools/hook-me-up/README.md#first-run).

4. **Methodology:** run `bash "$HOME/fde-toolkit/methodology/agent-workflow/install.sh"`
   and show its dry-run plan. After approval, repeat with `--yes`.
   It links skills, roles and Herdr templates, backing up originals under
   `~/.local/share/agent-workflow/backups/`. For partial setups use
   `--only claude|codex|hc`; the checker reports omitted components.
   [Installation details](methodology/agent-workflow/README.md#instalación-local).

5. **Personal precedence, only with permission.** This prevents Superpowers
   routing before the methodology loads. Preserve content and avoid duplicates:

   ```sh
   line='Para trabajo de desarrollo usa la skill agent-workflow; su triaje decide qué skills de Superpowers aplican.'
   for file in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
     mkdir -p "$(dirname "$file")"
     grep -Fqx "$line" "$file" 2>/dev/null || printf '\n%s\n' "$line" >> "$file"
   done
   ```

6. **Herdr:** open Desktop and run `herdr-app ls`. Reuse the space named after
   the target repo; stop if ambiguous. Only if absent, after permission, run this
   with the command's working directory set to that project:
   `herdr-app do space.new --name "$(basename "$(git rev-parse --show-toplevel)")" --folder "$(git rev-parse --show-toplevel)"`.
   Optional private `herdr_space` overrides: [Herdr protocol](methodology/agent-workflow/skills/agent-workflow/references/herdr-hc.md).

7. **Verify:** `bash "$HOME/fde-toolkit/scripts/check-setup.sh"` (offline, read-only).
   Fix each ✗; confirm cached Superpowers is enabled in both menus. For a smoke
   test, prepare a disposable project's **own Herdr space using step 6**, then ask:
   “usa la metodología agent-workflow para corregir estas dos erratas concretas
   en archivos conocidos, nivel N1”. Confirm N1 and a Codex tab in that space.
   A single-value change may be N0 and stay inline.

8. **Update/remove:** repeat step 2, then steps 3–4, including dry-run and consent.
   To remove Hook Me Up, after permission, preview hook removal without prompts:
   `env -u HOOK_ME_UP_YES HOOK_ME_UP_NO_TTY=1 bash "$HOME/fde-toolkit/tools/hook-me-up/uninstall.sh"`.
   Show both clients' removal previews as in step 3; after explicit yes for those
   changes, run `HOOK_ME_UP_YES=1 bash "$HOME/fde-toolkit/tools/hook-me-up/uninstall.sh"`.
   To keep Codex hooks, append `--no-codex` to both commands; the app and agent stay
   installed if those hooks still call the app. Keep `CODEX_HOME` the same for both
   runs. After hook removal, restart existing Claude Code and Codex CLI sessions.
   Preview methodology removal with `bash "$HOME/fde-toolkit/methodology/agent-workflow/install.sh" --uninstall`;
   after approval repeat with `--yes`. Uninstall restores originals; destinations
   no longer owned are preserved and reported. Missing backups are reported;
   owned links are still removed and unresolved entries stay in the manifest.
   Keep the checkout until its links are removed. [Details](methodology/agent-workflow/README.md#instalación-local).
