# Native dispatch in Claude Code

Dispatch and precedence: [SKILL.md](../SKILL.md#default-assignment).
Check that the agents are available in `claude agents` and that the runtime
supports the requested model. In a plugin, use the name exposed by that plugin;
for local installation, use the filename under `~/.claude/agents/`.

1. Resolve the base and worktree; use EnterWorktree when appropriate and available.
   Do not copy .env or inherit data from another environment.
2. Prepare a self-contained brief: role, absolute path, applicable instructions,
   scope, base, criteria, approved plan, validation, limits and delivery.
3. For planificador/revisor, make a fresh Agent call with the role's `subagent_type`
   and an explicit `model` from roles.md. Do not fork or use an earlier session.
4. Save the implementer's ID. Send feedback with SendMessage to the same ID;
   at most two rounds. A fresh reviewer for each stable SHA after repairs.
5. At N1 the coordinator reads the diff and verifies, without a reviewer. N0 is inline.
6. Archive reports and requested/confirmed models in private state.

If Agent or the model is unavailable, declare the limitation and do not present
an inline reading as independent review. Present a human gate with a reviewable
artifact only if approval is missing; preserve all existing approvals.
