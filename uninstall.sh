#!/bin/bash
# Hook Me Up uninstaller.
#
#   curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/uninstall.sh | bash
#
# Removes Hook Me Up's hooks from ~/.claude/settings.json (after showing the diff and
# asking). Only then does it stop the agent and remove the app, its LaunchAgent and its
# support folder; if the hooks stay, everything else stays too. Settings backups
# (settings.json.bak-*) and the log are left where they are.
#
# Environment:
#   HOOK_ME_UP_YES=1         change ~/.claude/settings.json without asking
#   HOOK_ME_UP_DRY_LAUNCH=1  do not use launchctl (tests)
#   HOOK_ME_UP_NO_TTY=1      behave as if there were no terminal to ask (tests, and the
#                            Claude Code plugin, which asks in the chat instead)
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
  say "Settings backups (settings.json.bak-*) were left in ~/.claude."
}

main "$@"
