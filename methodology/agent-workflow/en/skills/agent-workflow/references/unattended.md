# Unattended mode

Only work on tickets explicitly enabled by the user, one at a time per profile.
Each assignment uses its own worktree; Codex workers or an equivalent runner with `claude -p`.
The dispatcher checks the worker's receipt against git and gh; unverified ready becomes draft or blocked.
A human gate ends blocked with a reviewable artifact and its hash.
It only reopens with explicit user approval of that artifact's exact hash.
Enqueue and resume are not approval; the worker does not approve itself.
Never start, enqueue, approve or execute work on your own initiative.
Implementation and profiles live in private configuration under `~/.config/agent-workflow`.
