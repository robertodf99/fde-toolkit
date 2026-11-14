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
#   HOOK_ME_UP_NO_ONBOARDING=1  skip the notification check after starting the agent
#   HOOK_ME_UP_DRY_LAUNCH=1     do not use launchctl or start the app (tests)
#   HOOK_ME_UP_NO_TTY=1         behave as if there were no terminal to ask (tests)
#
# Everything runs from main(), called on the last line, so a download cut short runs
# nothing.
set -euo pipefail

REPO="robertodf99/hook-me-up"
LABEL="io.github.robertodf99.hook-me-up"
BUNDLE_ID="io.github.robertodf99.hook-me-up"

say() { printf '%s\n' "$*"; }
warn() { printf 'hook-me-up: %s\n' "$*" >&2; }
die() {
  warn "$*"
  exit 1
}
dry_launch() { [ "${HOOK_ME_UP_DRY_LAUNCH:-0}" = "1" ]; }
has_tty() { [ "${HOOK_ME_UP_NO_TTY:-0}" != "1" ] && (exec </dev/tty) 2>/dev/null; }
# Whether this hook-me-up-setup has the command $2 (older releases only have install and
# uninstall): its usage lists the commands it knows.
setup_has() {
  local usage
  usage="$("$1" --help 2>&1 </dev/null)" || true
  case "$usage" in *"hook-me-up-setup $2"*) return 0 ;; esac
  return 1
}

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
    rm -f "$WORK/package.zip" "$WORK/package.zip.sha256" "$WORK/notifications"
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
  local fresh=1 # a first install, not an upgrade
  if [ -e "$APP" ]; then fresh=0; fi
  rm -rf "$APPS/.Hook Me Up.app.installing" "$APPS/.Hook Me Up.app.previous"
  REPLACING=1
  local stage="$APPS/.Hook Me Up.app.installing"
  ditto "$new" "$stage"

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
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>$BUNDLE_ID</string>
	</array>
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
  local started=0
  if dry_launch; then
    say "LaunchAgent written (not started: HOOK_ME_UP_DRY_LAUNCH=1)."
  elif launchctl bootstrap "gui/$(id -u)" "$plist"; then
    started=1
    say "Started the Hook Me Up agent (it starts again at login)."
  else
    warn "launchctl could not start the agent; opening the app instead."
    open "$APP" || true
  fi

  # --- Notifications ----------------------------------------------------------------
  # Waits for macOS's notification question to be answered, reports the settings, shows
  # a test notification and opens System Settings when something needs changing (on an
  # upgrade, only when notifications are off). Never reads stdin; never fails the install.
  local notifications="" skipped=""
  if [ "${HOOK_ME_UP_NO_ONBOARDING:-0}" = "1" ]; then
    skipped="HOOK_ME_UP_NO_ONBOARDING=1"
  elif ! setup_has "$setup" notifications; then
    skipped="this version's hook-me-up-setup has no notifications command"
  elif dry_launch; then
    skipped="HOOK_ME_UP_DRY_LAUNCH=1"
  elif [ "$started" != "1" ]; then
    skipped="the agent was not started by launchctl"
  fi
  if [ -n "$skipped" ]; then
    say "Notification check skipped ($skipped)."
  else
    local wait=10 open_settings=--open-settings-if-off
    if has_tty; then wait=60; fi
    if [ "$fresh" = "1" ]; then open_settings=--open-settings; fi
    say ""
    "$setup" notifications --wait "$wait" --test "$open_settings" --result-file "$WORK/notifications" </dev/null || true
    notifications="$(cat "$WORK/notifications" 2>/dev/null || true)"
  fi

  # --- Next steps -------------------------------------------------------------------
  local allow='  - Allow notifications for "Hook Me Up" when macOS asks
    (or System Settings > Notifications > Hook Me Up).'
  local alerts='  - In System Settings > Notifications > Hook Me Up, set the notification style to
    "Alerts", so requests stay on screen until you answer them.'
  local turn_on='  - Turn on notifications for "Hook Me Up" in System Settings > Notifications, with
    the style set to "Alerts".'
  local restart='  - Restart the Claude Code sessions that are already running, so they load the hooks.'
  local steps
  case "$notifications" in
    ready) steps="$restart" ;;
    not-alerts) steps="$alerts"$'\n'"$restart" ;;
    off) steps="$turn_on"$'\n'"$restart" ;;
    *) steps="$allow"$'\n'"$alerts"$'\n'"$restart" ;;
  esac
  local doctor=""
  if setup_has "$setup" doctor; then
    doctor=$'\n'"Something not working? Check the installation with:"$'\n'"  \"$setup\" doctor"$'\n'
  fi
  cat <<EOF

Hook Me Up is installed. Hooks in ~/.claude/settings.json: $hooks.

Next steps:
$steps
$doctor
Run this installer again to upgrade. To uninstall:
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash
EOF
}

main "$@"
