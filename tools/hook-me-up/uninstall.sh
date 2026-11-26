#!/bin/bash
# Hook Me Up uninstaller.
#
#   curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/uninstall.sh | bash
#
# Removes Hook Me Up's hooks from ~/.claude/settings.json (after showing the diff and
# asking). Only then does it stop the agent and remove the app, its LaunchAgent, its
# support folder and the editor extension (from VS Code, VS Code Insiders, Cursor and
# Windsurf, with each command-line tool found); if the hooks stay, everything else stays
# too. Settings backups (settings.json.bak-*) and the log are left where they are.
#
# Environment:
#   HOOK_ME_UP_YES=1         change ~/.claude/settings.json without asking
#   HOOK_ME_UP_DRY_LAUNCH=1  do not use launchctl (tests)
#   HOOK_ME_UP_NO_TTY=1      behave as if there were no terminal to ask (tests, and the
#                            Claude Code plugin, which asks in the chat instead)
#   HOOK_ME_UP_TEST_APPLICATIONS=<dir>  look for the editors' apps only under <dir> (tests)
#   HOOK_ME_UP_TEST_EDITOR_TIMEOUT=<s>  stop an editor's tool after <s> seconds, not 120 (tests)
#
# Everything runs from main(), called on the last line, so a download cut short runs
# nothing.
set -euo pipefail

LABEL="io.github.robertodf99.hook-me-up"

say() { printf '%s\n' "$*"; }
warn() { printf 'hook-me-up: %s\n' "$*" >&2; }
die() {
  warn "$*"
  exit 1
}
dry_launch() { [ "${HOOK_ME_UP_DRY_LAUNCH:-0}" = "1" ]; }
has_tty() { [ "${HOOK_ME_UP_NO_TTY:-0}" != "1" ] && (exec </dev/tty) 2>/dev/null; }

# The command-line tool of each VS Code-family editor found, one per line: the editor's
# name, a tab, the tool's path. The tool on PATH, else the one inside the app in
# /Applications or ~/Applications. The same in install.sh and uninstall.sh.
editor_clis() {
  local entry cli app name dir found folders=(/Applications "$HOME/Applications")
  # Tests look elsewhere, so the editors on the test machine don't count.
  if [ -n "${HOOK_ME_UP_TEST_APPLICATIONS:-}" ]; then folders=("$HOOK_ME_UP_TEST_APPLICATIONS"); fi
  for entry in "code|Visual Studio Code|VS Code" "code-insiders|Visual Studio Code - Insiders|VS Code Insiders" \
    "cursor|Cursor|Cursor" "windsurf|Windsurf|Windsurf"; do
    IFS='|' read -r cli app name <<<"$entry"
    found="$(command -v "$cli" 2>/dev/null || true)"
    case "$found" in /*) ;; *) found="" ;; esac
    if [ -z "$found" ]; then
      for dir in "${folders[@]}"; do
        if [ -x "$dir/$app.app/Contents/Resources/app/bin/$cli" ]; then
          found="$dir/$app.app/Contents/Resources/app/bin/$cli"
          break
        fi
      done
    fi
    if [ -n "$found" ]; then printf '%s\t%s\n' "$name" "$found"; fi
  done
}
# Runs a command and stops it after $1 seconds, so an editor's tool that hangs can't hang
# this script: its exit status, or 124 when it was stopped. The tools are wrappers that
# start the editor's own process and wait for it (they don't exec it), so the wrapper's
# children are stopped first; whatever they started in turn is not looked for. The same
# in both scripts.
run_limited() {
  local seconds="$1" pid tenths=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$tenths" -ge $((seconds * 10)) ]; then
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
    tenths=$((tenths + 1))
  done
  wait "$pid"
}

# Quits a Hook Me Up started outside launchd: only processes whose executable is exactly
# this installed app's.
quit_running_app() {
  local executable="$1" pid
  dry_launch && return 0
  for pid in $(pgrep -x HookMeUp 2>/dev/null || true); do
    if [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "$executable" ]; then kill -TERM "$pid" 2>/dev/null || true; fi
  done
}

main() {
  case "${HOME:-}" in
    "" | "/") die "HOME is not set." ;;
  esac
  [ -d "$HOME" ] || die "HOME ($HOME) is not a folder."

  local app="$HOME/Applications/Hook Me Up.app"
  local support="$HOME/Library/Application Support/hook-me-up"
  local settings="$HOME/.claude/settings.json"
  local setup="$app/Contents/MacOS/hook-me-up-setup"

  # The hooks go first: while they remain, the agent and the app stay, so the hooks
  # never point at nothing.
  local removed=0
  if [ ! -f "$settings" ]; then
    removed=1
  elif [ ! -x "$setup" ]; then
    warn "$setup is missing: remove the hook-me-up entries from $settings by hand."
    removed=1
  else
    local args=(uninstall --settings "$settings" --hook "$app/Contents/MacOS/hook-me-up" --state "$support/setup-state.json")
    if [ "${HOOK_ME_UP_YES:-0}" = "1" ]; then
      if "$setup" "${args[@]}" --yes; then removed=1; fi
    elif has_tty; then
      if "$setup" "${args[@]}" </dev/tty; then removed=1; fi
    else
      "$setup" "${args[@]}" --dry-run || true
      say ""
      say "No terminal to ask, so ~/.claude/settings.json was not changed."
    fi
  fi

  if [ "$removed" != "1" ]; then
    say "The hooks are still in $settings, so Hook Me Up keeps running and stays installed."
    say "Run this again in a terminal, or with HOOK_ME_UP_YES=1, to finish."
    exit 0
  fi

  if ! dry_launch; then launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; fi
  quit_running_app "$app/Contents/MacOS/HookMeUp"
  rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
  rm -rf "$HOME/Applications/Hook Me Up.app"
  rm -rf "$HOME/Library/Application Support/hook-me-up"
  say "Stopped the agent and removed $app, its LaunchAgent and $support."
  local editor cli
  local limit="${HOOK_ME_UP_TEST_EDITOR_TIMEOUT:-120}"
  case "$limit" in "" | *[!0-9]*) limit=120 ;; esac
  # An editor without the extension refuses (exit 1): nothing to say then.
  while IFS=$'\t' read -r editor cli; do
    if run_limited "$limit" "$cli" --uninstall-extension hook-me-up.hook-me-up >/dev/null 2>&1 </dev/null; then
      say "Removed the Hook Me Up extension from $editor."
    fi
  done < <(editor_clis)
  say "Settings backups (settings.json.bak-*) were left in ~/.claude."
}

main "$@"
