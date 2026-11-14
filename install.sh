#!/bin/bash
# Hook Me Up installer (and upgrader: run it again to update).
#
#   curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/install.sh | bash
#
# Installs ~/Applications/Hook Me Up.app, adds the hooks to ~/.claude/settings.json
# (after showing the diff and asking), and starts the menu-bar agent at login.
#
# Environment:
#   HOOK_ME_UP_VERSION=vX.Y.Z   install that release instead of the latest
#   HOOK_ME_UP_YES=1            change ~/.claude/settings.json without asking
#   HOOK_ME_UP_ZIP=<path>       install a local package (its .sha256 must sit next to it)
#   HOOK_ME_UP_CLAUDE_APP=<path> Claude.app to take the icon from ("-": keep the ✻ icon)
#   HOOK_ME_UP_DRY_LAUNCH=1     do not use launchctl or start the app (tests)
#   HOOK_ME_UP_NO_TTY=1         behave as if there were no terminal to ask (tests)
#
# Everything runs from main(), called on the last line, so a download cut short runs
# nothing.
set -euo pipefail

REPO="robertodf99/hook-me-up"
LABEL="io.github.robertodf99.hook-me-up"

say() { printf '%s\n' "$*"; }
warn() { printf 'hook-me-up: %s\n' "$*" >&2; }
die() {
  warn "$*"
  exit 1
}
dry_launch() { [ "${HOOK_ME_UP_DRY_LAUNCH:-0}" = "1" ]; }
has_tty() { [ "${HOOK_ME_UP_NO_TTY:-0}" != "1" ] && (exec </dev/tty) 2>/dev/null; }

# Quits a Hook Me Up started outside launchd (e.g. with `open`): only processes whose
# executable is exactly this installed app's.
quit_running_app() {
  local executable="$1" pid
  dry_launch && return 0
  for pid in $(pgrep -x HookMeUp 2>/dev/null || true); do
    if [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "$executable" ]; then kill -TERM "$pid" 2>/dev/null || true; fi
  done
}

# On any exit: while the app is being replaced, put the previous version back; always
# remove the staging copy and the downloads.
on_exit() {
  if [ "${REPLACING:-0}" = "1" ]; then
    if [ ! -e "$APP" ] && [ -e "$APPS/.Hook Me Up.app.previous" ]; then
      mv "$APPS/.Hook Me Up.app.previous" "$APP" && warn "the installation failed; the previous version was put back."
    fi
    rm -rf "$APPS/.Hook Me Up.app.installing"
  fi
  if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
    rm -rf "$WORK/unpacked"
    rm -f "$WORK/package.zip" "$WORK/package.zip.sha256" "$WORK/AppIcon.icns"
    rmdir "$WORK" 2>/dev/null || true
  fi
}

main() {
  # --- Checks -----------------------------------------------------------------------
  [ "$(uname -s)" = "Darwin" ] || die "Hook Me Up runs on macOS only."
  local macos
  macos="$(sw_vers -productVersion)"
  [ "${macos%%.*}" -ge 14 ] || die "macOS 14 or later is needed (this Mac has $macos)."
  case "${HOME:-}" in
    "" | "/") die "HOME is not set." ;;
  esac
  [ -d "$HOME" ] || die "HOME ($HOME) is not a folder."

  APPS="$HOME/Applications"
  APP="$APPS/Hook Me Up.app"
  local support="$HOME/Library/Application Support/hook-me-up"
  local agents="$HOME/Library/LaunchAgents"
  local plist="$agents/$LABEL.plist"
  local log="$HOME/Library/Logs/hook-me-up.log"
  local settings="$HOME/.claude/settings.json"
  REPLACING=0
  trap on_exit EXIT
  trap 'exit 130' INT TERM

  if [ ! -d "$HOME/.claude" ]; then
    warn "Claude Code was not found (~/.claude is missing). The app is installed anyway;"
    warn "install Claude Code, then run this installer again to add the hooks."
  fi

  # --- Download and verify ----------------------------------------------------------
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/hmu-install.XXXXXX")"
  [ -n "$WORK" ] && [ -d "$WORK" ] || die "could not create a temporary folder."

  if [ -n "${HOOK_ME_UP_ZIP:-}" ]; then
    [ -f "$HOOK_ME_UP_ZIP" ] || die "$HOOK_ME_UP_ZIP not found."
    [ -f "$HOOK_ME_UP_ZIP.sha256" ] || die "$HOOK_ME_UP_ZIP.sha256 not found."
    cp "$HOOK_ME_UP_ZIP" "$WORK/package.zip"
    cp "$HOOK_ME_UP_ZIP.sha256" "$WORK/package.zip.sha256"
    say "Installing Hook Me Up from $HOOK_ME_UP_ZIP"
  else
    local tag="${HOOK_ME_UP_VERSION:-}" release
    if [ -z "$tag" ]; then
      local no_release="could not find the latest release of $REPO on GitHub (none published yet, or the API rate limit). Pick a version with HOOK_ME_UP_VERSION=vX.Y.Z."
      release="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null)" || die "$no_release"
      tag="$(printf '%s' "$release" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
      [ -n "$tag" ] || die "$no_release"
    fi
    [[ "$tag" =~ ^v?[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || die "invalid version [$tag]."
    local name="hook-me-up-${tag#v}-macos.zip"
    local base="https://github.com/$REPO/releases/download/$tag"
    say "Downloading Hook Me Up $tag"
    curl -fsSL -o "$WORK/package.zip" "$base/$name" ||
      die "could not download $name for $tag. Check the version (HOOK_ME_UP_VERSION) and your connection."
    curl -fsSL -o "$WORK/package.zip.sha256" "$base/$name.sha256" ||
      die "could not download the checksum of $name."
  fi
  local expected actual
  expected="$(awk '{ print $1; exit }' "$WORK/package.zip.sha256")"
  actual="$(shasum -a 256 "$WORK/package.zip" | awk '{ print $1 }')"
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || die "checksum mismatch: the download is not the published package."
  ditto -x -k "$WORK/package.zip" "$WORK/unpacked" || die "the package could not be unpacked."
  local new="$WORK/unpacked/HookMeUp.app" executable
  for executable in HookMeUp hook-me-up hook-me-up-setup; do
    [ -x "$new/Contents/MacOS/$executable" ] || die "the package has no $executable."
  done

  # --- Install the app --------------------------------------------------------------
  # The agent is stopped first, so the old app is not running while it is replaced.
  if ! dry_launch; then launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; fi
  quit_running_app "$APP/Contents/MacOS/HookMeUp"

  mkdir -p "$APPS"
  # An earlier run that stopped half-way may have left the previous version aside.
  if [ ! -e "$APP" ] && [ -e "$APPS/.Hook Me Up.app.previous" ]; then
    mv "$APPS/.Hook Me Up.app.previous" "$APP"
  fi
  rm -rf "$APPS/.Hook Me Up.app.installing" "$APPS/.Hook Me Up.app.previous"
  REPLACING=1
  local stage="$APPS/.Hook Me Up.app.installing"
  ditto "$new" "$stage"

  # The official Claude icon, when the Claude app is installed; else the ✻ icon.
  local claude_app="${HOOK_ME_UP_CLAUDE_APP:-}" candidate
  if [ -z "$claude_app" ]; then
    for candidate in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
      if [ -d "$candidate" ]; then
        claude_app="$candidate"
        break
      fi
    done
  fi
  if [ -n "$claude_app" ] && [ "$claude_app" != "-" ]; then
    if "$stage/Contents/MacOS/hook-me-up-setup" icon "$claude_app" "$WORK/AppIcon.icns" >/dev/null &&
      cp "$WORK/AppIcon.icns" "$stage/Contents/Resources/AppIcon.icns" &&
      codesign --force --deep --sign - "$stage" 2>/dev/null &&
      codesign --verify --strict --deep "$stage" 2>/dev/null; then
      say "Icon: the official icon of the installed Claude app"
    else
      warn "could not apply the Claude icon; keeping the ✻ icon."
      rm -rf "$APPS/.Hook Me Up.app.installing"
      ditto "$new" "$stage"
    fi
  fi

  if [ -e "$APP" ]; then mv "$APP" "$APPS/.Hook Me Up.app.previous"; fi
  if [ "${HOOK_ME_UP_TEST_FAIL_AFTER_BACKUP:-0}" = "1" ]; then die "test failure after moving the previous version aside"; fi
  mv "$stage" "$APP"
  REPLACING=0
  rm -rf "$APPS/.Hook Me Up.app.previous"
  say "Installed $APP"

  # --- Claude Code hooks ------------------------------------------------------------
  local setup="$APP/Contents/MacOS/hook-me-up-setup" hooks="not added"
  mkdir -p "$(dirname "$support")"
  mkdir -p -m 700 "$support"
  chmod 700 "$support"
  local setup_args=(install --settings "$settings" --hook "$APP/Contents/MacOS/hook-me-up" --state "$support/setup-state.json")
  if [ ! -d "$HOME/.claude" ]; then
    hooks="skipped (no Claude Code)"
  elif [ "${HOOK_ME_UP_YES:-0}" = "1" ]; then
    if "$setup" "${setup_args[@]}" --yes; then hooks="added"; fi
  elif has_tty; then
    # stdin is the curl pipe: the question goes to the terminal.
    if "$setup" "${setup_args[@]}" </dev/tty; then hooks="added"; fi
  else
    "$setup" "${setup_args[@]}" --dry-run || true
    hooks="not added (no terminal to ask)"
    say ""
    say "No terminal to ask, so ~/.claude/settings.json was not changed. To add the hooks, run:"
    say "  \"$setup\" install --settings \"$settings\" --hook \"$APP/Contents/MacOS/hook-me-up\" --state \"$support/setup-state.json\""
    say "or run this installer again with HOOK_ME_UP_YES=1."
  fi

  # --- Start at login ---------------------------------------------------------------
  mkdir -p "$agents" "$(dirname "$log")"
  xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$(xml "$APP")/Contents/MacOS/HookMeUp</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardOutPath</key>
	<string>$(xml "$log")</string>
	<key>StandardErrorPath</key>
	<string>$(xml "$log")</string>
</dict>
</plist>
EOF
  plutil -lint -s "$plist" || die "the LaunchAgent file is invalid: $plist"
  if dry_launch; then
    say "LaunchAgent written (not started: HOOK_ME_UP_DRY_LAUNCH=1)."
  elif launchctl bootstrap "gui/$(id -u)" "$plist"; then
    say "Started the Hook Me Up agent (it starts again at login)."
  else
    warn "launchctl could not start the agent; opening the app instead."
    open "$APP" || true
  fi

  # --- Next steps -------------------------------------------------------------------
  cat <<EOF

Hook Me Up is installed. Hooks in ~/.claude/settings.json: $hooks.

Next steps:
  1. Allow notifications for "Hook Me Up" when macOS asks
     (or System Settings > Notifications > Hook Me Up).
  2. In the same place, set the notification style to "Alerts", so requests stay
     on screen until you answer them.
  3. Restart the Claude Code sessions that are already running, so they load the hooks.

Run this installer again to upgrade. To uninstall:
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash
EOF
}

main "$@"
