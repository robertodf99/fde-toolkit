# FDE Toolkit playbook

Keep this public toolkit simple: each tool or methodology owns what it needs,
and the root helps people discover, install and check those modules.
Start with [README.md](README.md), follow [INSTALL.md](INSTALL.md) for setup,
and read [AGENTS.md](AGENTS.md) before making changes.

## Repository layout

```text
tools/<tool>/                     Tool source, docs, tests and packaging
methodology/<name>/               Methodology, skills, roles and tests
scripts/                          Small checks shared by the toolkit
.claude-plugin/marketplace.json   Optional Claude Code plugin catalogue
.github/workflows/                Module CI and release workflows
README.md / INSTALL.md            Discovery / user setup
AGENTS.md / Makefile              Contributor instructions / task shortcuts
```

- `tools/<tool>/` owns its implementation, dependencies, build and release assets.
  [Hook Me Up](tools/hook-me-up/README.md) is the current example.
- `methodology/<name>/` owns its practices, runtime adapters and validation.
  [agent-workflow](methodology/agent-workflow/README.md) is the current example.
- Root [scripts](scripts/) check shared concerns: marketplace consistency and
  local setup. Keep module-specific scripts inside their module.
- The [marketplace](.claude-plugin/marketplace.json) points to optional plugins
  within this checkout; it does not replace a module's installer or tests.
- The root [Makefile](Makefile) delegates tool tasks and exposes shared checks.
  Build details stay in the module's own build files.

## Add a module

- [ ] Create `tools/<tool>/` or `methodology/<name>/` with only the files it needs.
- [ ] Write its README: purpose, requirements, usage, checks and removal if installed.
      Link to deeper docs rather than duplicating them or adding empty scaffolding.
- [ ] Add its own tests and document how to run them; test installers in a fake HOME.
- [ ] Add an installer/uninstaller if needed, following the consent rules below.
- [ ] Add a row to the root [README table](README.md).
- [ ] For an optional Claude Code plugin, put its manifest at
      `<source>/.claude-plugin/plugin.json` and add a local source entry to
      [marketplace.json](.claude-plugin/marketplace.json); validate it with
      [check-marketplace.sh](scripts/check-marketplace.sh) and module plugin checks.
- [ ] Add its own CI workflow with path filters for the module and shared dependencies.
      See [Hook Me Up CI](.github/workflows/ci.yml) and
      [methodology CI](.github/workflows/methodology.yml).
- [ ] Add a root [Makefile](Makefile) shortcut if useful; prefix new targets with the
      module name to avoid collisions with Hook Me Up's generic targets.
- [ ] Add an [INSTALL.md](INSTALL.md) step if users must install anything.

Tools: use `<tool>-vX.Y.Z` tags when publishing packages; see
[Hook Me Up's release workflow](.github/workflows/release.yml).
Methodologies: preview installation and restore originals on removal; keep private
profiles, overrides and run state outside the repository.

## Working as an FDE

- **Consent first.** Before installing software or changing user configuration,
  show the proposed diff or dry-run and ask for approval. Use `--yes` (or
  `HOOK_ME_UP_YES=1`) only after an explicit yes. Follow [INSTALL.md](INSTALL.md).
- **Preserve user files.** Back up originals, write configuration atomically,
  and reject a write if the file changed since it was read. See Hook Me Up's
  [security model](tools/hook-me-up/README.md#security-model).
- **Fail open.** Hook errors must leave the normal terminal approval flow usable;
  an error is never an approval or denial. See the same security model.
- **Keep public content generic.** No secrets, credentials, real customer data or
  customer names. Keep private profiles and reports outside this repository;
  follow the [delivery rules](methodology/agent-workflow/skills/agent-workflow/references/delivery.md).
- **Keep maintenance small.** Write short docs that link to the source of truth.
  Keep scripts focused, with shared checks at the root and tool scripts local.
- **Isolate each change.** Use a worktree per change, one writer and the independent
  review required by [agent-workflow](methodology/agent-workflow/skills/agent-workflow/SKILL.md).
  Follow its triage and role contracts instead of duplicating them here.
  Make small, focused commits and submit changes through PRs.
- **Verify before claiming success.** Reproduce bugs before fixing them, run real
  behavior checks, and report omitted checks. Types or a build alone do not prove
  behavior; see the methodology's [verification practices](methodology/agent-workflow/skills/agent-workflow/references/superpowers.md).

## Useful tools

These are already used or referenced by the toolkit; setup is in [INSTALL.md](INSTALL.md).
Use them plus the toolkit's own modules, listed in the [README](README.md).

| Tool | Use |
|---|---|
| [Claude Code](https://code.claude.com/docs/en/setup) | Work on repositories with an agent, skills and plugins. |
| [Codex CLI](https://developers.openai.com/codex/cli) | Run coding tasks and the methodology's implementation roles. |
| [Herdr Desktop + Core](https://herdr.dev/download/) | Dispatch roles into visible terminals and exchange task results. |
| [Superpowers](https://github.com/obra/superpowers#installation) | Supply the development practices selected by agent-workflow triage. |
| [jq](https://jqlang.org/download/) | Inspect JSON output, including Herdr space discovery. |
| [gh](https://cli.github.com/) | Work with GitHub PRs and releases, and verify release attestations. |

## Before handing off

Run the changed module's documented checks and `scripts/check-marketplace.sh`
from the root; report results and omissions.
