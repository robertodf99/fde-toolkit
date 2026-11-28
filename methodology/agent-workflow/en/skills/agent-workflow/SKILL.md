---
name: agent-workflow
description: Use when the user asks to plan or carry out development with the multi-agent methodology, or receives a brief for one of its roles.
---

# Multi-agent methodology

Scale the process to the scope and consequences. The same source serves Claude Code, Codex and Herdr Core.
If the first message assigns a role, perform only that role and return its delivery contract; do not
orchestrate agents.

## Default assignment

The coordinator is the user's session. The planner and reviewer use **Claude Opus**; implementers use
**Codex**: gpt-6-luna/high for mechanical work, gpt-6.1-sol/high for normal work and gpt-6.1-sol/xhigh for
sensitive work. The canonical dispatch is [Herdr](references/herdr-hc.md): run the roles required by triage
in order, one per phase, waiting for each result before the next. Native dispatch uses a single runtime as a
non-interactive fallback: `claude -p`, `codex exec` or unattended mode ("Herdr does not apply"). In an
interactive session, Herdr missing or unresponsive = report a blocker, with no automatic fallback.

## Precedence and skill selection

User instructions > repo AGENTS.md / CLAUDE.md > this skill > Superpowers. This skill decides which
Superpowers apply. At N0–N2 **DO NOT invoke brainstorming or writing-plans**, even if their descriptions
require it. The repo's own diagnosis, testing or validation skills take precedence. Respect the level set by
the user and existing approvals.

## Coordinator triage

Read the brief and repo instructions first. Classify by observable criteria, not line count or tracker
estimates:

| Level | Condition | Execution |
|---|---|---|
| N0 | One line or value, with no behaviour change to discuss | Coordinator inline |
| N1 | Complete requirement, known location, local effect, no design or sensitive areas, concrete check | Only implementador-simple |
| N2 | Understood behaviour or bug with a clear symptom, no open design or sensitive areas | Implementador + revisor |
| N3 | Sensitive area, open designs, several modules or independent tasks, missing criteria, or explicit request for a planner | Planificador + implementador or implementador-delicado + revisor |

An understood change across several files for the same behaviour does not imply several modules or tasks.
Tests for an endpoint are part of its task. "Plan" at N1/N2 means a brief plan by the coordinator, without
an independent planner. Only "use a planner" requires that role outside N3. When unsure, choose the lower
level, except for sensitive areas; once set, only escalate upwards. Authentication, SQL, migrations,
security, irreversible operations and deployment are sensitive, as are any areas identified by the repo.

## Flow by level

- **N0:** edit inline and verify the specific effect.
- **N1:** the coordinator prepares a brief with criteria and a check; dispatch
  implementador-simple. No reviewer: the coordinator reads the diff and verifies.
- **N2:** brief and short plan by the coordinator, implementer, reproduction before
  bug fixes, behaviour tests and a reviewer with fresh context on the final SHA.
  No independent planner is required.
- **N3:** independent planner. The coordinator uses brainstorming **only** for
  open design and writing-plans **only** for more than one task. After design or
  planning, return to this N3 flow: **DO NOT follow the handoff chain**
  brainstorming → writing-plans → SDD/executing-plans. Present an artifact if approval
  is missing; preserve existing approvals. Implementador-delicado for sensitive areas,
  implementador otherwise. A fresh reviewer on each corrected SHA.

For "plan", deliver the plan and stop without implementing, regardless of level. Always use
verification-before-completion. At N2/N3 use test-driven-development for features/bugs and
systematic-debugging for bugs or unexpected failures. With Herdr **DO NOT invoke subagent-driven-development
or requesting-code-review**; use their [extracted practices](references/superpowers.md). The reviewer is
always this methodology's revisor role. **Never executing-plans**: the coordinator only implements at N0.

## Execution limits

Only one implementer writes; keep their session for feedback. At most two repair rounds per assignment,
persisted on resume. Each review uses fresh context and a stable diff; do not review while code changes. Do
not replace the implementer or reset rounds to bypass the limit. When exhausted, escalate outstanding
findings with evidence and an individual disposition.

Roles do not create agents, publish, change the tracker or merge. The coordinator must not initiate merge,
deploy, release or closure either. Do not select tickets or queues automatically. Do not invent approvals: a
pending gate requires an artifact and blocked status. Do not copy .env or use real data or credentials.
Escalate new scope and sensitive areas before editing.

## Context and dispatch

Identify the repo by its worktree and instructions. Resolve the base branch before creating a worktree or
PR. A private profile under `~/.config/agent-workflow/profiles/` is optional; if it contradicts the repo,
clarify before writing. Without a profile, the brief suffices. Do not inherit architecture, business rules,
standards, states or prefixes from other projects.

Project language: repo AGENTS.md / CLAUDE.md → optional `language` field (`es|en`) in the private profile →
predominant language of existing commits and docs → Spanish. The coordinator states the language in the
brief; if absent, roles apply this rule.

With a ticket, read criteria, relationships and blockers from the tracker via MCP (e.g. Linear) and verify
project identity. Tracker changes require user instructions or an explicit repo rule and are carried out by
the coordinator.

Read [roles.md](references/roles.md) for models, contracts and permissions. In interactive sessions follow
[Herdr](references/herdr-hc.md) and the optional overrides in `~/.config/agent-workflow/HERDR.md`. Each role
appears under its parent in the sidebar agent list; inspect it with `terminal.peek` and convert it to a tab
with `terminal.keep` if requested. If required Herdr is unavailable, report a blocker, with no native
substitution.

Native references: [Claude Code](references/claude-code.md) and [Codex](references/codex.md). This
methodology authorises the models in roles.md for that dispatch. If you cannot delegate, declare the
limitation; an inline review is not independent.

## Delivery and records

Commits, PRs, tickets, plans, reviews, code comments and role reports use the project language resolved
above. Follow [delivery.md](references/delivery.md): SHA, files, evidence per criterion, actual and omitted
checks, risks, rounds and disposition of each finding. The coordinator independently verifies the SHA, diff,
worktree status and evidence. Record IDs, requested/confirmed models and approvals without secrets in
private state, never in the public repo. Optional private unattended mode: [contract and
approvals](references/unattended.md).
