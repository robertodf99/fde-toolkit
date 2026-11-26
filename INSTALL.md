# Set up FDE Toolkit

Tell your agent: **“Follow https://github.com/robertodf99/fde-toolkit/blob/main/INSTALL.md”.**

**Agent rules:** ask before installing software or changing user configuration;
show the proposed changes first. Never read, paste or use credentials, buy a plan,
or change global settings silently. Let the user handle sign-in. Stop and report
any failed step; preserve existing files and approvals.

1. **Check prerequisites.** Hook Me Up needs macOS 14+ (`sw_vers -productVersion`);
   on Linux, skip it and install just the methodology. Check the terminal tools:

   ```sh
   for tool in git claude codex herdr-app herdr-core python3 jq; do
     command -v "$tool" || { printf 'Missing: %s\n' "$tool"; exit 1; }
   done
   ```

   If missing, ask before following the official installation instructions:
   [Git](https://git-scm.com/downloads/), [Claude Code](https://code.claude.com/docs/en/setup),
   [Codex CLI](https://developers.openai.com/codex/cli),
   [Herdr Desktop + Core](https://herdr.dev/download/),
   [Python 3.9+](https://www.python.org/downloads/) and [jq](https://jqlang.org/download/).
   Install/enable [Superpowers](https://github.com/obra/superpowers#installation)
   in **both** Claude Code and Codex: Claude `/plugin install superpowers@claude-plugins-official`;
   Codex `/plugins` → search Superpowers → Install Plugin. These are agent-menu
   commands, not shell commands. [gh](https://cli.github.com/) is optional.

2. **Use a stable checkout.** Default: `~/fde-toolkit`; choose another permanent
   path if needed. Methodology symlinks point here: never use `/tmp` or a worktree.
   If the folder exists, confirm it is this repository and has no local changes;
   stop on a mismatch or conflict. Then run:

   ```sh
   toolkit_dir="$HOME/fde-toolkit"
   if [ -d "$toolkit_dir/.git" ]; then
     git -C "$toolkit_dir" pull --ff-only
   else
     git clone https://github.com/robertodf99/fde-toolkit "$toolkit_dir"
   fi
   cd "$toolkit_dir"
   ```

   Run the remaining setup commands from this checkout.

3. **Install Hook Me Up (Mac only), after permission.** It installs the app,
   login agent and editor extension, and previews changes to `~/.claude/settings.json`:

   ```sh
   HOOK_ME_UP_YES=0 bash tools/hook-me-up/install.sh
   ```

   The installer asks through `/dev/tty`. Without a TTY it leaves settings alone:
   show the printed diff to the user, then **only after their explicit yes** run
   `HOOK_ME_UP_YES=1 bash tools/hook-me-up/install.sh`.
   Allow notifications, select **Alerts**, and restart existing Claude Code sessions.
   Verify with `"$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup" doctor`.
   See [first run and troubleshooting](tools/hook-me-up/README.md#first-run) for detail.

4. **Install the methodology.** Run `bash methodology/agent-workflow/install.sh`
   first and show its dry-run plan. After approval, run
   `bash methodology/agent-workflow/install.sh --yes`.
   It links skills, five roles per runtime and Herdr templates; originals and their
   manifest go under `~/.local/share/agent-workflow/backups/`.
   For partial setups, use `--only claude|codex|hc`; the final checker targets the
   full setup and will report omitted components. See [installation details](methodology/agent-workflow/README.md#instalación-local).

5. **Propose personal precedence.** Explain this prevents Superpowers routing
   before the methodology loads. **Only with permission**, append this exact line
   to the two personal instruction files, preserving content and avoiding duplicates:

   ```sh
   line='Para trabajo de desarrollo usa la skill agent-workflow; su triaje decide qué skills de Superpowers aplican.'
   for file in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
     mkdir -p "$(dirname "$file")"
     grep -Fqx "$line" "$file" 2>/dev/null || printf '\n%s\n' "$line" >> "$file"
   done
   ```

6. **Prepare Herdr.** Open Herdr Desktop. In each target project, run
   `herdr-app ls` and reuse the space named after the repo. Only if missing, and
   after permission, create it with
   `herdr-app do space.new --name "$(basename "$(git rev-parse --show-toplevel)")" --folder "$(git rev-parse --show-toplevel)"`.
   If names are ambiguous, stop. Optional private `herdr_space` overrides and the
   launch protocol are in [Herdr instructions](methodology/agent-workflow/skills/agent-workflow/references/herdr-hc.md).

7. **Verify:** `bash "$toolkit_dir/scripts/check-setup.sh"` (offline, read-only).
   Fix each ✗; cached Superpowers files still need to be enabled in both menus.
   With permission for a small change, ask in a disposable project:
   “usa la metodología agent-workflow para corregir estas dos erratas concretas
   en archivos conocidos, nivel N1”. Confirm N1 and a Codex tab in that project's
   Herdr space. A single-value change may be N0 and stay inline.

8. **Update or remove.** Update with `git -C "$toolkit_dir" pull --ff-only`,
   then repeat steps 3–4 (dry-run and consent before writes). To uninstall, after
   permission run `bash "$toolkit_dir/tools/hook-me-up/uninstall.sh"` on Mac;
   its settings consent rule is the same as step 3. Preview methodology removal
   with `bash "$toolkit_dir/methodology/agent-workflow/install.sh" --uninstall --restore`,
   then repeat with `--yes` after approval. Keep the checkout until its links are
   removed. [Backup and restore details](methodology/agent-workflow/README.md#instalación-local).
