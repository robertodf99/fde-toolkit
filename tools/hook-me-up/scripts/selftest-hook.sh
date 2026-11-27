#!/bin/bash
# Self-test of the built hook binary with no agent listening: every invocation must
# print nothing on stdout, exit 0 and return quickly (Claude Code then shows its own
# terminal dialog). Always uses a private socket path (--socket), so it can never reach
# a real running agent.
#
# Usage: scripts/selftest-hook.sh [path/to/hook-me-up]
set -u

BIN="${1:-.build/release/hook-me-up}"
if [ ! -x "$BIN" ]; then
  echo "selftest: $BIN not found or not executable (run: make build)" >&2
  exit 1
fi

TMP="$(mktemp -d /tmp/hmu-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
NONE="$TMP/agent.sock"   # nothing ever listens here
STALE="$TMP/stale.sock"  # a socket file left behind by a crashed agent
/usr/bin/python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()' "$STALE"

# PermissionRequest example from code.claude.com/docs/en/hooks.
DOCS='{
  "session_id": "abc123",
  "transcript_path": "/home/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
  "cwd": "/home/...",
  "permission_mode": "default",
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf node_modules",
    "description": "Remove node_modules directory"
  },
  "permission_suggestions": [
    {
      "type": "addRules",
      "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf node_modules" }],
      "behavior": "allow",
      "destination": "localSettings"
    }
  ]
}'
NOTIFICATION='{"session_id":"abc123","cwd":"/home/...","hook_event_name":"Notification","message":"Claude needs your input","notification_type":"elicitation_dialog"}'
STOP='{"session_id":"abc123","cwd":"/home/...","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done. Details follow."}'
PROMPT='{"session_id":"abc123","cwd":"/home/...","hook_event_name":"UserPromptSubmit","prompt":"hi"}'

now() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

failures=0
check() {
  local name="$1" input="$2"
  shift 2
  local start end out rc elapsed
  start="$(now)"
  out="$(printf '%s' "$input" | "$BIN" "$@" 2>/dev/null)"
  rc=$?
  end="$(now)"
  elapsed="$(/usr/bin/perl -e "printf '%.3f', $end - $start")"
  if [ -z "$out" ] && [ "$rc" -eq 0 ] && /usr/bin/perl -e "exit(!($elapsed < 1.0))"; then
    echo "PASS  $name (${elapsed}s)"
  else
    echo "FAIL  $name: exit=$rc elapsed=${elapsed}s stdout=[$out]"
    failures=$((failures + 1))
  fi
}

check "permission, docs example, no agent"     "$DOCS"         permission --timeout 600 --socket "$NONE"
check "permission, docs example, stale socket" "$DOCS"         permission --timeout 600 --socket "$STALE"
check "notify, no agent"                       "$NOTIFICATION" notify --socket "$NONE"
check "finished, no agent"                     "$STOP"         finished --socket "$NONE"
check "clear, no agent"                        "$PROMPT"       clear --socket "$NONE"
check "clear, stale socket"                    "$PROMPT"       clear --socket "$STALE"
check "garbage stdin"                          "not json"      permission --timeout 600 --socket "$NONE"
check "empty stdin"                            ""              permission --timeout 600 --socket "$NONE"
check "unknown mode"                           "$DOCS"         approve --socket "$NONE"
check "bad timeout"                            "$DOCS"         permission --timeout abc --socket "$NONE"
check "no arguments"                           "$DOCS"

check "Codex permission, no agent" "$DOCS" permission --client codex --socket "$NONE"
check "Codex finished, no agent" "$STOP" finished --client codex --socket "$NONE"
check "Codex clear, no agent" "$PROMPT" clear --client codex --socket "$NONE"
check "Codex notify is unsupported" "$NOTIFICATION" notify --client codex --socket "$NONE"
check "Codex permission, stale socket" "$DOCS" permission --client codex --socket "$STALE"
check "Codex garbage stdin" "not json" permission --client codex --socket "$NONE"
check "Codex unknown argument" "$DOCS" permission --client codex --unknown value --socket "$NONE"
check "unknown client" "$DOCS" permission --client future --socket "$NONE"

if [ "$failures" -eq 0 ]; then
  echo "selftest: all checks passed"
else
  echo "selftest: $failures check(s) failed"
  exit 1
fi
