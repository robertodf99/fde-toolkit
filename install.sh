#!/bin/bash
# Hook Me Up compatibility entry point, from a checkout or via curl | bash.
# HOOK_ME_UP_REF chooses the downloaded script's ref (default: main).
# Keep main on the last line so a truncated download runs nothing.
set -euo pipefail

main() {
  local source="${BASH_SOURCE[0]:-}" directory script
  if [ -n "$source" ] && [ -f "$source" ]; then
    directory="$(cd "$(dirname "$source")" && pwd)"
    if [ -f "$directory/tools/hook-me-up/install.sh" ]; then
      exec "$directory/tools/hook-me-up/install.sh" "$@"
    fi
  fi
  script="$(curl -fsSL "https://raw.githubusercontent.com/robertodf99/fde-toolkit/${HOOK_ME_UP_REF:-main}/tools/hook-me-up/install.sh")" || return $?
  exec bash -c "$script" -- "$@"
}

main "$@"
