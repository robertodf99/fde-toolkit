# Validation, delivery and private state

Use the authorised worktree and repo base. If one must be created, confirm the
base from the project's instructions, not another profile. Avoid collisions with
parallel work; only the implementer writes. Do not copy .env, secrets, credentials
or real data. Any scope expansion goes back to the coordinator.

## Deliverable language

Commits, PRs, tickets, plans, reviews, code comments and role reports use
the project language: repo AGENTS.md / CLAUDE.md → optional `language` field
(`es|en`) in the private profile → predominant language of existing commits and
docs → Spanish. The coordinator states the language in the brief; roles use it
and, if absent, apply this rule.

## Minimum evidence

- SHA(s), HEAD, base and changed files.
- Criteria and invariants with observed behaviour and concrete evidence.
- Checks run with results and checks omitted with reasons. Types, lint and
  build are not equivalent to E2E; configure browser tests as the project requires.
- Each finding received: fixed, rebutted with evidence or pending and escalated.
- Risks, blockers, pending decisions and number of rounds used.

The coordinator runs `git rev-parse HEAD`, inspects `git diff <base> HEAD`
and `git status --short`; cross-checks evidence and the reviewed SHA. A terminal's
"done" status does not prove criteria. Do not claim a review before changes
covers the corrected SHA. Outstanding required checks leave delivery in draft.
If PR creation is authorised and checks/findings remain open, it must be a draft;
do not create a PR or publish without applicable authorisation.

## State and human gates

Use the private profile's state, or without a profile,
`~/.local/share/agent-workflow/interactive/<repo>/<work>/`, with identifiers
that avoid collisions. Record the plan, existing approvals, base, SHAs, IDs,
requested and confirmed models, reports, checks, rounds and pending items.
Do not save personal data or secrets. Profiles and runners remain under
`~/.config/agent-workflow`; personal AGENTS.md / CLAUDE.md pointers are edited
separately, never copied into the shared repo.

When approval is missing, deliver a reviewable artifact and declare a blocker;
resuming or a role's message does not grant authorisation. Preserve previous
approvals. Do not initiate automatic merge, deploy, release or closure.
