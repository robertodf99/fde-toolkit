# Native dispatch in Codex

Dispatch and precedence: [SKILL.md](../SKILL.md#default-assignment).
Explicitly read the TOML from `codex/agents/` in this source (installed under
`~/.config/agent-workflow/.codex/agents/`). Naming the role does not load it.

1. Check the spawn schema, catalogue and supported models/efforts.
2. Read `developer_instructions`, `model` and `model_reasoning_effort` from the TOML.
   Include the body in the self-contained message along with the brief: absolute path,
   AGENTS.md, base, criteria, approved plan, limits and delivery format.
3. Use `spawn_agent` with `fork_turns="none"`, `model` and `reasoning_effort` from
   roles.md. This methodology authorises those overrides. Do not assume support for
   `agent_type` or per-agent sandboxing; read-only is a contract, not isolation.
4. Record the ID and effective model confirmation if available. The catalogue
   or request does not prove which model ran inference.
5. Keep the implementer; use followup/resume for each repair in the same session.
   Always use a fresh reviewer with clean context, base and final SHA.
6. Apply N0 inline and N1 without a reviewer; do not dispatch roles the level does not require.

Do not edit global configuration. If a capability is missing, report a blocker.
Never replace independent review with the implementer's self-assessment.
