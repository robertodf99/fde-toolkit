# FDE Toolkit playbook

Keep this public toolkit simple: each tool or methodology owns what it needs,
and the root helps people discover, install and check those modules.
Start with [README.md](README.md), follow [INSTALL.md](INSTALL.md) for setup,
and read [AGENTS.md](AGENTS.md) before making changes.

## Repository layout

```text
tools/<tool>/                     Tool source, docs, tests and packaging
methodology/<name>/               Methodology, skills, roles and tests
scripts/                         Small checks shared by the toolkit
.claude-plugin/marketplace.json   Optional Claude Code plugin catalogue
.github/workflows/               Module CI and release workflows
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

A self-contained module has a README covering purpose, requirements, usage and
validation; its own tests; and an installer/uninstaller if installation is needed.
An optional plugin lives with the module and has its own manifest and checks.
Link to deeper docs only when they are useful; avoid adding empty scaffolding.

Give each module its own CI workflow with path filters for that module and the
shared files it depends on. See [tool CI](.github/workflows/ci.yml) and
[methodology CI](.github/workflows/methodology.yml).
For packaged tool releases, use `<tool>-vX.Y.Z` tags to keep versions independent;
[Hook Me Up's release workflow](.github/workflows/release.yml) handles
`hook-me-up-v*`. Add release automation only when a module needs it.

## Add a tool

- [ ] Create `tools/<tool>/` with its source and only the supporting files needed.
- [ ] Write its README: purpose, requirements, use, checks and removal if installed.
- [ ] Add tests and document how to run them from the module directory.
- [ ] Add an installer/uninstaller if needed, following the consent rules below.
- [ ] Add a row to the root [README table](README.md).
- [ ] If exposing a Claude Code plugin, add its manifest and a local source entry
      to [marketplace.json](.claude-plugin/marketplace.json); validate it with
      [check-marketplace.sh](scripts/check-marketplace.sh).
- [ ] Add module CI with path filters; use tool-prefixed tags if releasing packages.
- [ ] Add a root [Makefile](Makefile) target if a shortcut is useful.
- [ ] Add a step to [INSTALL.md](INSTALL.md) if users must install anything.

## Add a methodology

- [ ] Create `methodology/<name>/` with the practices and runtime files it needs.
- [ ] Write its README: purpose, usage, supported runtimes and validation.
- [ ] Add checks for its contracts and adapters; test any installer in a fake HOME.
- [ ] If installation is needed, provide a preview and a way to restore originals.
- [ ] Add a row to the root [README table](README.md).
- [ ] If it is also a Claude Code plugin, add its manifest and local marketplace
      entry; run [check-marketplace.sh](scripts/check-marketplace.sh).
- [ ] Add its own CI with path filters, including relevant shared files.
- [ ] Add a root [Makefile](Makefile) target if useful, and an [INSTALL.md](INSTALL.md)
      step if users need to install it.

Use [agent-workflow](methodology/agent-workflow/README.md) as a working example,
keeping personal profiles, overrides and run state outside the public module.

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
- **Verify before claiming success.** Reproduce bugs before fixing them, run real
  behavior checks, and report omitted checks. Types or a build alone do not prove
  behavior; see the methodology's [verification practices](methodology/agent-workflow/skills/agent-workflow/references/superpowers.md).
- **Keep delivery reviewable.** Make small, focused commits and submit changes
  through PRs. Follow the methodology's delivery rules for approvals and evidence.

## Useful tools

These are already used or referenced by the toolkit; setup is in [INSTALL.md](INSTALL.md).

| Tool | Use |
|---|---|
| [Claude Code](https://code.claude.com/docs/en/setup) | Work on repositories with an agent, skills and plugins. |
| [Codex CLI](https://developers.openai.com/codex/cli) | Run coding tasks and the methodology's implementation roles. |
| [Herdr Desktop + Core](https://herdr.dev/download/) | Dispatch roles into visible terminals and exchange task results. |
| [Superpowers](https://github.com/obra/superpowers#installation) | Supply the development practices selected by agent-workflow triage. |
| [jq](https://jqlang.org/download/) | Inspect JSON output, including Herdr space discovery. |
| [gh](https://cli.github.com/) | Work with GitHub PRs and releases, and verify release attestations. |
| [Hook Me Up](tools/hook-me-up/README.md) | Answer Claude Code and Codex CLI from native macOS notifications. |
| [agent-workflow](methodology/agent-workflow/README.md) | Coordinate scoped implementation, independent review and evidence. |

## Before handing off

Run the changed module's documented checks, then `scripts/check-marketplace.sh`
and `git diff --check` from the root. Check relative links when editing docs.
Report actual results and omissions using the methodology's delivery contract.
