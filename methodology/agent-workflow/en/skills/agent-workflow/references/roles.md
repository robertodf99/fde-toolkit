# Roles and contracts

Dispatch and precedence: [SKILL.md](../SKILL.md#default-assignment).

Models are dispatch preferences, not promises of cost or quality.
Check the runtime catalogue and schema; record the requested and confirmed model
separately. If a required capability is missing, report a blocker.
Do not change global configuration to force it.

| Role | Native Claude | Native Codex (effort) | Herdr (CLI, model) |
|---|---|---|---|
| planificador | opus, high | gpt-6.1-sol, high | Claude opus, dontAsk |
| implementador-simple | sonnet, high | gpt-6-luna, high | Codex gpt-6-luna, high |
| implementador | opus, high | gpt-6.1-sol, high | Codex gpt-6.1-sol, high |
| implementador-delicado | opus, xhigh | gpt-6.1-sol, xhigh | Codex gpt-6.1-sol, xhigh |
| revisor | opus, high | gpt-6.1-sol, high | Claude opus, dontAsk |

Planner and reviewer use Opus in all Claude dispatches.
Public names use hyphens; Codex TOML files/names use
`implementador_simple` and `implementador_delicado` for local compatibility.
All three formats keep the same body, checked by `tests/check-roles.sh`.

## Contracts

- Planner: inspection only; current behaviour, reproduction, assigned level
  N0–N3 and reasons, criteria, exclusions, steps, validation and blockers.
- Implementers: sole writer in the specified worktree; SHA, files, evidence per
  criterion, checks run/omitted and risks. The sensitive role includes invariants.
  Each finding received includes a disposition and evidence.
- Reviewer: fresh context; final SHA reviewed, verdict, findings with priority,
  file/line, consequence and reproduction or reasoning; unproven criteria and
  limitations. Only binding repo standards.

No role creates agents, publishes, changes the tracker or merges. The coordinator
keeps the implementer's session for at most two repair rounds;
planner and reviewers are retired after their reports are recorded.
Triage is already complete: no worker invokes process skills that dispatch
agents or ask the user questions; return doubts and blockers in the final report.

## Sensitive areas and permissions

Read AGENTS.md / CLAUDE.md for domain areas. Authentication, SQL, migrations,
security, critical architecture, irreversible changes and deployment require
escalation. If implementador-simple discovers them, it stops writing and returns the
assignment to the coordinator; it does not decide a design independently.

Native Claude disables editing for planner/reviewer, but Bash and MCP remain
subject to the read-only contract; they do not provide technical isolation.
Native Codex does not offer per-agent sandboxing in the API described here;
the TOML is an instruction source, not a permission guarantee. In Herdr, implementers
use `--sandbox danger-full-access`: `workspace-write` makes `.git` read-only in
this flow and blocks commits. The contract limits their actions to the assignment.
`--no-daemon` and `-c approval_policy="never"` are mandatory for Codex inside
hc. Together with danger-full-access, they prevent invisible approvals blocking
the worker; they do not expand scope or authorise new actions.

In Herdr, planner and reviewer use `--permission-mode dontAsk`, allow
`Bash,Read,Grep,Glob,WebFetch,WebSearch` and deny
`Edit,Write,NotebookEdit,Agent,Skill,AskUserQuestion,ExitPlanMode,Workflow,Artifact,SendMessage`.
Both commands end in ` --` to separate the prompt from variadic lists.
They do not use plan mode. Bash remains unrestricted: read-only is a role contract,
not technical isolation.
Native Claude agents retain their frontmatter and their own limits.
