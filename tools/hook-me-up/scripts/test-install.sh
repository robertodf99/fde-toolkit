#!/bin/bash
# Runs install.sh and uninstall.sh against a throwaway HOME, the way `curl | bash` runs
# them (script on stdin), with a locally built package and without the real launchctl.
# Checks: the hooks are added (and only with consent); `hook-me-up-setup doctor --home`
# reports them (and the app and LaunchAgent); install warns about another installation's
# hooks (an uninstall command for an absolute path, by hand otherwise); the notification
# check is skipped without launchctl, when opted out or when the package's
# hook-me-up-setup is too old to have it; with stand-ins for launchctl and the check, the
# flags it gets on a first install and on an upgrade, and the next steps for each result;
# a second install changes nothing; a truncated download or a failed install leaves
# everything as it was; uninstall restores the original settings, removes the support
# folder and leaves the backups; a declined uninstall leaves the agent installed; the
# editor extension, with stand-ins for the editors' command-line tools (on PATH or inside
# a fake app), is added with --force and the app's .vsix, skipped when opted out or when
# no tool is found, never fails the install (a tool that hangs is stopped with the
# process it started), and is removed by uninstall; and the real HOME is never touched.
# Every run gets a PATH of system folders only and a fake Applications folder, so the
# real editors are never asked anything.
#
# Usage: scripts/test-install.sh   (HOOK_ME_UP_ZIP=<zip> to reuse a package)
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP="${HOOK_ME_UP_ZIP:-}"
if [ -z "$ZIP" ]; then
  VERSION=test CODESIGN_IDENTITY=- ./scripts/package.sh >/dev/null
  ZIP="$PWD/.build/dist/hook-me-up-test-macos.zip"
fi

REAL_HOME="$HOME"
# The scripts run with system folders only on PATH (plus stand-ins where a test adds them),
# so no real editor's command-line tool can be found.
SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
for cli in code code-insiders cursor windsurf; do
  if PATH="$SAFE_PATH" command -v "$cli" >/dev/null 2>&1; then
    echo "test-install: $cli is on $SAFE_PATH; refusing to run (it would be a real editor's)" >&2
    exit 1
  fi
done
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/hmu-test-install.XXXXXX")"
case "$WORKDIR" in
  */hmu-test-install.*) ;;
  *)
    echo "unexpected temporary folder [$WORKDIR]" >&2
    exit 1
    ;;
esac
# TMPDIR may end in "/": normalise, so paths compare as the tools write them.
WORKDIR="$(cd "$WORKDIR" && pwd)"
case "$WORKDIR" in
  /*/hmu-test-install.*) ;;
  *)
    echo "unexpected temporary folder [$WORKDIR]" >&2
    exit 1
    ;;
esac
if [ "${HOOK_ME_UP_KEEP_TEST_DIR:-0}" = "1" ]; then echo "keeping $WORKDIR"; else trap 'rm -rf "$WORKDIR"' EXIT; fi
FAKE="$WORKDIR/home"
LOGS="$WORKDIR/logs"
mkdir -p "$FAKE" "$LOGS"

failures=0
check() {
  if eval "$2"; then echo "PASS  $1"; else
    echo "FAIL  $1"
    failures=$((failures + 1))
  fi
}
fingerprint() {
  for path in "$REAL_HOME/.claude/settings.json" "$REAL_HOME/Applications/Hook Me Up.app" \
    "$REAL_HOME/Library/LaunchAgents/io.github.robertodf99.hook-me-up.plist" \
    "$REAL_HOME/Library/Application Support/hook-me-up"; do
    if [ -e "$path" ]; then stat -f '%N %i %m %z' "$path"; else echo "$path absent"; fi
  done
  if [ -f "$REAL_HOME/.claude/settings.json" ]; then shasum -a 256 "$REAL_HOME/.claude/settings.json"; fi
}
tree_state() { # every folder (name, mode) and file (name, mode, size, mtime, content) in the fake HOME
  # A folder's own mtime only records renames inside it (e.g. the old app moved aside
  # and back), so folders are compared by their entries instead.
  (cd "$FAKE" && find . -type d -print0 | sort -z | xargs -0 stat -f '%N %p' &&
    find . ! -type d -print0 | sort -z | xargs -0 stat -f '%N %p %z %m' &&
    find . -type f -print0 | sort -z | xargs -0 shasum -a 256)
}
same_tree() { # expected state: on a difference, show it
  local now
  now="$(tree_state)"
  [ "$1" = "$now" ] && return 0
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$now") | head -n 20 >&2
  return 1
}
run() { # script, extra env... (the script arrives on stdin, as with curl | bash)
  local script="$1"
  shift
  env HOME="$FAKE" HOOK_ME_UP_ZIP="$ZIP" HOOK_ME_UP_DRY_LAUNCH=1 HOOK_ME_UP_NO_TTY=1 PATH="$SAFE_PATH" \
    HOOK_ME_UP_TEST_APPLICATIONS="$WORKDIR/no-applications" "$@" bash <"$script"
}
run_truncated() { # script, fraction of its lines to keep (e.g. 1/2)
  local lines
  lines="$(($(wc -l <"$1") * ${2%/*} / ${2#*/}))"
  head -n "$lines" "$1" | env HOME="$FAKE" HOOK_ME_UP_ZIP="$ZIP" HOOK_ME_UP_DRY_LAUNCH=1 HOOK_ME_UP_NO_TTY=1 \
    PATH="$SAFE_PATH" HOOK_ME_UP_TEST_APPLICATIONS="$WORKDIR/no-applications" HOOK_ME_UP_YES=1 bash
}
json_equal() { /usr/bin/python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])))' "$1" "$2"; }

BEFORE="$(fingerprint)"
SETTINGS="$FAKE/.claude/settings.json"
mkdir -p "$FAKE/.claude"
cat >"$WORKDIR/original.json" <<'EOF'
{"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}
EOF
cp "$WORKDIR/original.json" "$SETTINGS"
APP="$FAKE/Applications/Hook Me Up.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)"
PLIST="$FAKE/Library/LaunchAgents/io.github.robertodf99.hook-me-up.plist"
HOOK_COMMAND="'$APP/Contents/MacOS/hook-me-up'"

echo "--- a truncated download does nothing"
EMPTY_STATE="$(tree_state)"
for part in 1/2 3/4; do
  run_truncated install.sh "$part" >"$LOGS/truncated-install-${part/\//-of-}.txt" 2>&1 || true
  check "install.sh cut at $part changes nothing" 'same_tree "$EMPTY_STATE"'
done

echo "--- install without a terminal and without HOOK_ME_UP_YES"
run install.sh >"$LOGS/install-1.txt" 2>&1
check "install succeeds" "true"
check "app installed" '[ -x "$APP/Contents/MacOS/HookMeUp" ] && [ -x "$APP/Contents/MacOS/hook-me-up" ]'
check "app signature valid" 'codesign --verify --strict --deep "$APP" 2>/dev/null'
check "icon present" '[ -s "$APP/Contents/Resources/AppIcon.icns" ]'
ditto -x -k "$ZIP" "$WORKDIR/package"
check "app installed exactly as packaged (signature intact)" 'diff -r -q "$WORKDIR/package/HookMeUp.app" "$APP"'
check "LaunchAgent written and valid" 'plutil -lint -s "$PLIST"'
associated() { /usr/libexec/PlistBuddy -c "Print :AssociatedBundleIdentifiers:0" "$PLIST" 2>/dev/null; }
check "LaunchAgent names the app (Login Items)" '[ "$(associated)" = "$BUNDLE_ID" ]'
check "support folder is private" '[ "$(stat -f %Lp "$FAKE/Library/Application Support/hook-me-up")" = 700 ]'
check "settings untouched without consent" 'cmp -s "$WORKDIR/original.json" "$SETTINGS"'
check "says how to add the hooks" 'grep -q "HOOK_ME_UP_YES=1" "$LOGS/install-1.txt"'
# doctor with --home: checks the app, its LaunchAgent and the hooks; skips launchd and the agent.
doctor() { "$APP/Contents/MacOS/hook-me-up-setup" doctor --home "$FAKE" >"$1" 2>&1; }
if doctor "$LOGS/doctor-1.txt"; then status=0; else status=$?; fi
check "doctor fails while the hooks are missing" '[ "$status" = 1 ]'
check "doctor names the missing hooks" 'grep -q "^FAIL  Hooks: .*has none of Hook Me Up" "$LOGS/doctor-1.txt"'
check "doctor gives the command that adds them" \
  'grep -q "Fix: Add them" "$LOGS/doctor-1.txt" && grep -F "$SETTINGS" "$LOGS/doctor-1.txt" | grep -q "hook-me-up-setup'"'"' install --settings"'
check "doctor passes the app and its LaunchAgent" \
  'grep -q "^PASS  App: " "$LOGS/doctor-1.txt" && grep -q "^PASS  LaunchAgent: io.github.robertodf99.hook-me-up starts this app" "$LOGS/doctor-1.txt"'
check "doctor skips launchd and the agent for another home" \
  'grep -q "^SKIP  Agent process: " "$LOGS/doctor-1.txt" && grep -q "^SKIP  Agent: " "$LOGS/doctor-1.txt"'
check "no notification check without launchctl" \
  'grep -q "^Notification check skipped (HOOK_ME_UP_DRY_LAUNCH=1)" "$LOGS/install-1.txt"'
check "System Settings not opened" '! grep -qi "opened system settings" "$LOGS/install-1.txt"'
check "no editor command-line tool: the extension is skipped, quietly" \
  'grep -qx "Editor extension skipped (no VS Code, VS Code Insiders, Cursor or Windsurf command-line tool found)." "$LOGS/install-1.txt" \
   && ! grep -q "could not add" "$LOGS/install-1.txt" && ! grep -q "Reload the windows" "$LOGS/install-1.txt"'
check "the app holds the editor extension" \
  '[ "$(unzip -Z1 "$APP/Contents/Resources/hook-me-up.vsix" | LC_ALL=C sort | tr "\n" " ")" = "[Content_Types].xml extension.vsixmanifest extension/LICENSE.txt extension/README.md extension/extension.js extension/package.json " ]'
check "next steps: allow notifications, Alerts, restart sessions; and the doctor" \
  'grep -q "Allow notifications for \"Hook Me Up\"" "$LOGS/install-1.txt" && grep -q "\"Alerts\"" "$LOGS/install-1.txt" \
   && grep -q "Restart the Claude Code sessions" "$LOGS/install-1.txt" && grep -q "hook-me-up-setup\" doctor$" "$LOGS/install-1.txt"'

echo "--- install with HOOK_ME_UP_YES=1"
run install.sh HOOK_ME_UP_YES=1 >"$LOGS/install-2.txt" 2>&1
check "hooks added for the five events" "/usr/bin/python3 - \"\$SETTINGS\" \"\$HOOK_COMMAND\" <<'PY'
import json, sys
settings, command = json.load(open(sys.argv[1])), sys.argv[2]
ours = {event for event, groups in settings['hooks'].items() for group in groups for hook in group['hooks']
        if hook['command'].startswith(command + ' ')}
sys.exit(ours != {'PermissionRequest', 'Notification', 'Stop', 'UserPromptSubmit', 'SessionEnd'}
         or settings['model'] != 'opus' or settings['hooks']['Stop'][0]['hooks'][0]['command'] != 'say done')
PY"
check "a backup was made" 'ls "$FAKE/.claude" | grep -q "^settings.json.bak-"'
cp "$SETTINGS" "$WORKDIR/after-install.json"
if doctor "$LOGS/doctor-2.txt"; then status=0; else status=$?; fi
check "doctor passes after the install" '[ "$status" = 0 ] && ! grep -q "^FAIL" "$LOGS/doctor-2.txt"'
check "doctor passes the app, LaunchAgent and hooks" \
  'grep -q "^PASS  App: " "$LOGS/doctor-2.txt" && grep -q "^PASS  LaunchAgent: " "$LOGS/doctor-2.txt" && grep -q "^PASS  Hooks: all five events" "$LOGS/doctor-2.txt"'
check "doctor changes nothing" 'cmp -s "$WORKDIR/after-install.json" "$SETTINGS"'

echo "--- the installer's warning about the hooks of another installation (dry runs)"
dry_install() { # settings file
  env HOME="$FAKE" "$APP/Contents/MacOS/hook-me-up-setup" install --settings "$1" \
    --hook "$APP/Contents/MacOS/hook-me-up" --state "$WORKDIR/dry-state.json" --dry-run
}
cat >"$WORKDIR/other-mixed.json" <<'EOF'
{"hooks": {"Stop": [{"hooks": [
  {"type": "command", "command": "'/Users/someone/Old/Hook Me Up.app/Contents/MacOS/hook-me-up' finished"},
  {"type": "command", "command": "~/Applications/Hook\\ Me\\ Up.app/Contents/MacOS/hook-me-up finished"}]}]}}
EOF
cat >"$WORKDIR/other-by-hand.json" <<'EOF'
{"hooks": {"Stop": [{"hooks": [
  {"type": "command", "command": "\"$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up\" finished"}]}]}}
EOF
dry_install "$WORKDIR/other-mixed.json" >"$LOGS/warn-mixed.txt" 2>&1
dry_install "$WORKDIR/other-by-hand.json" >"$LOGS/warn-by-hand.txt" 2>&1
check "an absolute path gets the uninstall command, the rest are removed by hand" \
  'grep -qx "If that copy is gone or unused, remove its hooks with:" "$LOGS/warn-mixed.txt" \
   && grep -q " uninstall --settings .* --hook '"'"'/Users/someone/Old/Hook Me Up.app/Contents/MacOS/hook-me-up'"'"'$" "$LOGS/warn-mixed.txt" \
   && grep -q "^Remove by hand from .*/other-mixed.json:$" "$LOGS/warn-mixed.txt" \
   && grep -qxF "  the entries that run ~/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up, which is not an absolute path" "$LOGS/warn-mixed.txt"'
check "with no absolute path, only the by-hand removal" \
  'grep -q "^If that copy is gone or unused, remove by hand from .*/other-by-hand.json:$" "$LOGS/warn-by-hand.txt" \
   && grep -qxF "  the entries that run \$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up, which is not an absolute path" "$LOGS/warn-by-hand.txt" \
   && ! grep -q " uninstall --settings" "$LOGS/warn-by-hand.txt"'
check "dry runs write nothing" '[ ! -e "$WORKDIR/dry-state.json" ] && cmp -s "$WORKDIR/after-install.json" "$SETTINGS"'

echo "--- install again (upgrade)"
# An agent installed by an older version: its plist has no AssociatedBundleIdentifiers.
/usr/libexec/PlistBuddy -c "Delete :AssociatedBundleIdentifiers" "$PLIST" 2>/dev/null || true
run install.sh HOOK_ME_UP_YES=1 >"$LOGS/install-3.txt" 2>&1
check "upgrade rewrites the LaunchAgent" '[ "$(associated)" = "$BUNDLE_ID" ] && plutil -lint -s "$PLIST"'
check "second install leaves the settings as they were" 'cmp -s "$WORKDIR/after-install.json" "$SETTINGS"'
check "second install reports no changes" 'grep -q "No changes" "$LOGS/install-3.txt"'
check "app still installed" '[ -x "$APP/Contents/MacOS/HookMeUp" ]'
check "no staging folders left" '! ls -a "$FAKE/Applications" | grep -q "^\.Hook Me Up"'
run install.sh HOOK_ME_UP_YES=1 HOOK_ME_UP_NO_ONBOARDING=1 >"$LOGS/install-no-onboarding.txt" 2>&1
check "HOOK_ME_UP_NO_ONBOARDING=1 skips the notification check" \
  'grep -q "^Notification check skipped (HOOK_ME_UP_NO_ONBOARDING=1)" "$LOGS/install-no-onboarding.txt"'

echo "--- a failed install leaves the installed app as it was"
INSTALLED_STATE="$(tree_state)"
for part in 1/2 3/4; do
  run_truncated install.sh "$part" >"$LOGS/truncated-upgrade-${part/\//-of-}.txt" 2>&1 || true
  check "install.sh cut at $part changes nothing" 'same_tree "$INSTALLED_STATE"'
done
printf 'not a zip' >"$WORKDIR/broken.zip"
shasum -a 256 "$WORKDIR/broken.zip" >"$WORKDIR/broken.zip.sha256"
if run install.sh HOOK_ME_UP_YES=1 HOOK_ME_UP_ZIP="$WORKDIR/broken.zip" >"$LOGS/install-broken.txt" 2>&1; then
  check "a broken package fails" "false"
else
  check "a broken package fails" "true"
fi
check "a broken package changes nothing" 'same_tree "$INSTALLED_STATE"'
if run install.sh HOOK_ME_UP_YES=1 HOOK_ME_UP_TEST_FAIL_AFTER_BACKUP=1 >"$LOGS/install-fail.txt" 2>&1; then
  check "a failure after moving the old app aside fails" "false"
else
  check "a failure after moving the old app aside fails" "true"
fi
check "the previous app is put back" 'same_tree "$INSTALLED_STATE"'

echo "--- uninstall without consent keeps everything working"
for part in 1/2 3/4; do
  run_truncated uninstall.sh "$part" >"$LOGS/truncated-uninstall-${part/\//-of-}.txt" 2>&1 || true
  check "uninstall.sh cut at $part changes nothing" 'same_tree "$INSTALLED_STATE"'
done
run uninstall.sh >"$LOGS/uninstall-1.txt" 2>&1
check "hooks kept" 'cmp -s "$WORKDIR/after-install.json" "$SETTINGS"'
check "app kept while hooks remain" '[ -d "$APP" ]'
check "agent left installed" '[ -f "$PLIST" ]'
check "says the agent keeps running" 'grep -q "keeps running" "$LOGS/uninstall-1.txt"'

echo "--- uninstall with HOOK_ME_UP_YES=1"
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-2.txt" 2>&1
check "settings restored to the original content" 'json_equal "$WORKDIR/original.json" "$SETTINGS"'
check "app removed" '[ ! -e "$APP" ]'
check "support folder removed" '[ ! -e "$FAKE/Library/Application Support/hook-me-up" ]'
check "LaunchAgent removed" '[ ! -e "$PLIST" ]'
check "backups left in place" 'ls "$FAKE/.claude" | grep -q "^settings.json.bak-"'
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-3.txt" 2>&1
check "uninstalling again is harmless" 'json_equal "$WORKDIR/original.json" "$SETTINGS"'

echo "--- a package whose hook-me-up-setup has no notifications command (0.1.x)"
# The same package with hook-me-up-setup replaced by a stand-in for 0.1.x: install and
# uninstall only (it hands them to the real one), anything else is a usage error.
OLD="$WORKDIR/old"
mkdir -p "$OLD"
ditto -x -k "$ZIP" "$OLD/unpacked"
OLD_MACOS="$OLD/unpacked/HookMeUp.app/Contents/MacOS"
mv "$OLD_MACOS/hook-me-up-setup" "$OLD_MACOS/hook-me-up-setup-current"
cat >"$OLD_MACOS/hook-me-up-setup" <<'STUB'
#!/bin/bash
case "${1:-}" in
  install | uninstall) exec "$(dirname "$0")/hook-me-up-setup-current" "$@" ;;
esac
echo "hook-me-up-setup: usage: hook-me-up-setup install|uninstall [--settings <path>] [--hook <path>] [--state <path>] [--timeout <seconds>] [--dry-run] [--yes]" >&2
exit 1
STUB
chmod +x "$OLD_MACOS/hook-me-up-setup"
(cd "$OLD/unpacked" && ditto -c -k --keepParent HookMeUp.app "$OLD/hook-me-up-old-macos.zip")
(cd "$OLD" && shasum -a 256 hook-me-up-old-macos.zip >hook-me-up-old-macos.zip.sha256)
if run install.sh HOOK_ME_UP_YES=1 HOOK_ME_UP_ZIP="$OLD/hook-me-up-old-macos.zip" >"$LOGS/install-old.txt" 2>&1; then
  status=0
else
  status=$?
fi
check "an older package installs" '[ "$status" = 0 ] && [ -x "$APP/Contents/MacOS/hook-me-up-setup-current" ]'
check "its missing notifications command is detected" \
  'grep -q "^Notification check skipped (this version.s hook-me-up-setup has no notifications command)" "$LOGS/install-old.txt"'
check "no doctor hint for a setup without doctor" '! grep -q "\" doctor" "$LOGS/install-old.txt"'
check "its hooks are added" 'grep -q "Hooks in ~/.claude/settings.json: added" "$LOGS/install-old.txt"'
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-old.txt" 2>&1
check "and uninstalled" 'json_equal "$WORKDIR/original.json" "$SETTINGS" && [ ! -e "$APP" ]'

echo "--- the notification check, with launchctl and hook-me-up-setup notifications stood in for"
# launchctl, pgrep and open stand in on PATH, so the real launchd, agent and apps are never
# touched; hook-me-up-setup's notifications command is a stand-in that records its
# arguments (refusing any it doesn't know) and reports $STUB_RESULT; its other commands
# go to the real one.
STUBS="$WORKDIR/stubs"
mkdir -p "$STUBS/bin"
cat >"$STUBS/bin/launchctl" <<'STUB'
#!/bin/bash
echo "launchctl $*" >>"$STUB_LOG"
if [ "${1:-}" = "bootstrap" ] && [ "${STUB_BOOTSTRAP_FAILS:-0}" = "1" ]; then exit 5; fi
exit 0
STUB
printf '#!/bin/bash\nexit 1\n' >"$STUBS/bin/pgrep"
printf '#!/bin/bash\necho "open $*" >>"$STUB_LOG"\n' >"$STUBS/bin/open"
chmod +x "$STUBS/bin/launchctl" "$STUBS/bin/pgrep" "$STUBS/bin/open"
ditto -x -k "$ZIP" "$STUBS/unpacked"
STUB_MACOS="$STUBS/unpacked/HookMeUp.app/Contents/MacOS"
mv "$STUB_MACOS/hook-me-up-setup" "$STUB_MACOS/hook-me-up-setup-current"
cat >"$STUB_MACOS/hook-me-up-setup" <<'STUB'
#!/bin/bash
if [ "${1:-}" != "notifications" ]; then exec "$(dirname "$0")/hook-me-up-setup-current" "$@"; fi
shift
echo "notifications $*" >>"$STUB_LOG"
# Never reads stdin: install.sh gives it /dev/null (a terminal would block it).
if ! [ /dev/stdin -ef /dev/null ]; then echo "stdin is not /dev/null" >>"$STUB_LOG"; fi
result=""
while [ $# -gt 0 ]; do
  case "$1" in
    --test | --open-settings | --open-settings-if-off) shift ;;
    --wait | --socket) shift 2 || exit 2 ;;
    --result-file) result="${2:-}"; shift 2 || exit 2 ;;
    *) echo "unknown flag $1" >>"$STUB_LOG"; exit 2 ;;
  esac
done
if [ -n "$result" ]; then printf '%s\n' "$STUB_RESULT" >"$result"; fi
echo "(stand-in) notification check: $STUB_RESULT"
STUB
chmod +x "$STUB_MACOS/hook-me-up-setup"
(cd "$STUBS/unpacked" && ditto -c -k --keepParent HookMeUp.app "$STUBS/hook-me-up-stub-macos.zip")
(cd "$STUBS" && shasum -a 256 hook-me-up-stub-macos.zip >hook-me-up-stub-macos.zip.sha256)
onboard() { # name, result, extra env...
  local name="$1" result="$2"
  shift 2
  : >"$LOGS/stub-$name.txt"
  run install.sh HOOK_ME_UP_YES=1 HOOK_ME_UP_DRY_LAUNCH=0 HOOK_ME_UP_ZIP="$STUBS/hook-me-up-stub-macos.zip" \
    PATH="$STUBS/bin:$SAFE_PATH" STUB_LOG="$LOGS/stub-$name.txt" STUB_RESULT="$result" "$@" >"$LOGS/install-$name.txt" 2>&1
}
next_steps() { sed -n '/^Next steps:/,/^Run this installer again/p' "$LOGS/install-$1.txt"; }
check "no app before the first install" '[ ! -e "$APP" ]'
onboard fresh ready
check "first install: launchctl bootstrap, then the check" \
  'grep -q "^launchctl bootstrap gui/" "$LOGS/stub-fresh.txt" && grep -q "^(stand-in) notification check: ready" "$LOGS/install-fresh.txt"'
check "first install: --wait 10 (no terminal), --test, --open-settings, --result-file" \
  'grep -qx "notifications --wait 10 --test --open-settings --result-file .*/notifications" "$LOGS/stub-fresh.txt"'
check "the check gets no unknown flag, and /dev/null as stdin" \
  '! grep -q -e "unknown flag" -e "stdin is not /dev/null" "$LOGS"/stub-*.txt'
check "ready: next steps only restart the sessions" \
  'next_steps fresh | grep -q "Restart the Claude Code sessions" && ! next_steps fresh | grep -q -e "Allow notifications" -e "notification style"'
# The real hook-me-up-setup takes exactly these flags (no wait; a socket nobody listens on).
args="$(sed -n 's/^notifications //p' "$LOGS/stub-fresh.txt" | sed -e 's/--wait 10/--wait 0/' -e 's/--result-file [^ ]*//')"
read -r -a args <<<"$args"
# With the stand-ins on PATH too, so it can never open the real System Settings.
: >"$LOGS/stub-real.txt"
env PATH="$STUBS/bin:$SAFE_PATH" STUB_LOG="$LOGS/stub-real.txt" "$STUB_MACOS/hook-me-up-setup-current" notifications \
  "${args[@]}" --socket "$WORKDIR/nobody.sock" --result-file "$WORKDIR/real-result" </dev/null \
  >"$LOGS/real-notifications.txt" 2>&1
check "the real notifications command takes the installer's flags" \
  '[ "$(cat "$WORKDIR/real-result")" = no-agent ] && grep -q -- "--open-settings" <<<"${args[*]}"'
check "and without an agent it opens nothing" '[ ! -s "$LOGS/stub-real.txt" ]'
onboard upgrade-banners not-alerts
check "upgrade: --open-settings-if-off" \
  'grep -qx "notifications --wait 10 --test --open-settings-if-off --result-file .*/notifications" "$LOGS/stub-upgrade-banners.txt"'
check "not Alerts: next steps set the style, then restart" \
  'next_steps upgrade-banners | grep -q "set the notification style to" && next_steps upgrade-banners | grep -q "Restart" \
   && ! next_steps upgrade-banners | grep -q "Allow notifications"'
onboard upgrade-off off
check "off: next steps turn notifications on, then restart" \
  'next_steps upgrade-off | grep -q "Turn on notifications" && ! next_steps upgrade-off | grep -q "Allow notifications"'
onboard upgrade-no-agent no-agent
check "no agent: the full next steps" \
  'next_steps upgrade-no-agent | grep -q "Allow notifications" && next_steps upgrade-no-agent | grep -q "notification style" \
   && next_steps upgrade-no-agent | grep -q "Restart"'
onboard bootstrap-fails ready STUB_BOOTSTRAP_FAILS=1
check "launchctl failing: no check, the app is opened instead" \
  'grep -q "^Notification check skipped (the agent was not started by launchctl)" "$LOGS/install-bootstrap-fails.txt" \
   && ! grep -q "^notifications" "$LOGS/stub-bootstrap-fails.txt" && grep -q "^open .*Hook Me Up.app" "$LOGS/stub-bootstrap-fails.txt"'
for n in fresh upgrade-banners upgrade-off upgrade-no-agent; do
  check "$n: the check ran exactly once" '[ "$(grep -c "^notifications " "$LOGS/stub-$n.txt")" = 1 ]'
done
check "every check got only known flags, and /dev/null as stdin" \
  '! grep -q -e "unknown flag" -e "stdin is not /dev/null" "$LOGS"/stub-*.txt'
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-stub.txt" 2>&1
check "and uninstalled" 'json_equal "$WORKDIR/original.json" "$SETTINGS" && [ ! -e "$APP" ]'

echo "--- the editor extension, with stand-ins for the editors' command-line tools"
# A stand-in records its arguments in $EDITOR_LOG (one line per call, with its own name)
# and exits with $EDITOR_STATUS; nothing reaches a real editor.
EDITORS="$WORKDIR/editors"
mkdir -p "$EDITORS/bin" "$EDITORS/apps/Cursor.app/Contents/Resources/app/bin"
cat >"$EDITORS/bin/code" <<'STUB'
#!/bin/bash
echo "$(basename "$0") $*" >>"$EDITOR_LOG"
if [ -n "${EDITOR_HANG:-}" ]; then
  # Like VS Code's own `code`, a wrapper whose editor process is a child it waits for.
  /bin/sleep 300 &
  echo "$!" >"$EDITOR_HANG"
  wait
fi
exit "${EDITOR_STATUS:-0}"
STUB
chmod +x "$EDITORS/bin/code"
cp "$EDITORS/bin/code" "$EDITORS/apps/Cursor.app/Contents/Resources/app/bin/cursor"
editor_run() { # name, script, extra env...
  local name="$1" script="$2"
  shift 2
  : >"$LOGS/editor-$name.txt"
  run "$script" HOOK_ME_UP_YES=1 PATH="$EDITORS/bin:$SAFE_PATH" EDITOR_LOG="$LOGS/editor-$name.txt" "$@" \
    >"$LOGS/$name.txt" 2>&1
}
VSIX="$APP/Contents/Resources/hook-me-up.vsix"
check "install.sh and uninstall.sh find the editors' tools the same way" \
  'diff <(sed -n "/^editor_clis() {/,/^}/p" install.sh) <(sed -n "/^editor_clis() {/,/^}/p" uninstall.sh) >/dev/null \
   && diff <(sed -n "/^run_limited() {/,/^}/p" install.sh) <(sed -n "/^run_limited() {/,/^}/p" uninstall.sh) >/dev/null'
editor_run install-code install.sh
check "code on PATH: the app's .vsix is installed with --force" \
  '[ "$(cat "$LOGS/editor-install-code.txt")" = "code --install-extension $VSIX --force" ]'
check "the installer says so, and to reload open windows" \
  'grep -qx "Added the Hook Me Up extension to VS Code." "$LOGS/install-code.txt" \
   && next_steps code | grep -q "Reload the windows of VS Code that were already open"'
editor_run install-cursor-app install.sh PATH="$SAFE_PATH" HOOK_ME_UP_TEST_APPLICATIONS="$EDITORS/apps"
check "a tool inside an editor's app is found too (Cursor)" \
  '[ "$(cat "$LOGS/editor-install-cursor-app.txt")" = "cursor --install-extension $VSIX --force" ] \
   && grep -qx "Added the Hook Me Up extension to Cursor." "$LOGS/install-cursor-app.txt"'
editor_run install-opt-out install.sh HOOK_ME_UP_NO_EDITOR_EXTENSION=1
check "HOOK_ME_UP_NO_EDITOR_EXTENSION=1: no tool is run" \
  '[ ! -s "$LOGS/editor-install-opt-out.txt" ] \
   && grep -qx "Editor extension skipped (HOOK_ME_UP_NO_EDITOR_EXTENSION=1)." "$LOGS/install-opt-out.txt"'
if editor_run install-tool-fails install.sh EDITOR_STATUS=1; then status=0; else status=$?; fi
editor_run install-tool-hangs install.sh EDITOR_HANG="$WORKDIR/hung-editor.pid" HOOK_ME_UP_TEST_EDITOR_TIMEOUT=1
hung="$(cat "$WORKDIR/hung-editor.pid" 2>/dev/null || true)"
gone() { # pid: true once it no longer runs (within 2 s)
  local tries=0
  while kill -0 "$1" 2>/dev/null; do
    [ "$tries" -ge 20 ] && return 1
    sleep 0.1
    tries=$((tries + 1))
  done
}
check "a tool that hangs is stopped with the process it started, and the install goes on" \
  '[ -n "$hung" ] && gone "$hung" && grep -q "could not add the Hook Me Up extension to VS Code" "$LOGS/install-tool-hangs.txt" \
   && grep -q "^Hook Me Up is installed" "$LOGS/install-tool-hangs.txt"'
if [ -n "$hung" ]; then kill "$hung" 2>/dev/null || true; fi
check "a tool that fails doesn't fail the install" \
  '[ "$status" = 0 ] && grep -q "could not add the Hook Me Up extension to VS Code" "$LOGS/install-tool-fails.txt" \
   && grep -q "^Hook Me Up is installed" "$LOGS/install-tool-fails.txt" && ! grep -q "Reload the windows" "$LOGS/install-tool-fails.txt"'
editor_run uninstall-code uninstall.sh
check "uninstall removes the extension with each tool" \
  '[ "$(cat "$LOGS/editor-uninstall-code.txt")" = "code --uninstall-extension hook-me-up.hook-me-up" ] \
   && grep -qx "Removed the Hook Me Up extension from VS Code." "$LOGS/uninstall-code.txt" && [ ! -e "$APP" ]'
editor_run reinstall-code install.sh
editor_run uninstall-not-there uninstall.sh EDITOR_STATUS=1
check "an editor without the extension: uninstall says nothing about it and succeeds" \
  'grep -q "^code --uninstall-extension" "$LOGS/editor-uninstall-not-there.txt" && [ ! -e "$APP" ] \
   && ! grep -q "extension" "$LOGS/uninstall-not-there.txt"'
run install.sh HOOK_ME_UP_YES=1 >"$LOGS/install-no-tool.txt" 2>&1
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-no-tool.txt" 2>&1
check "without any tool, uninstall succeeds without a word about the extension" \
  '[ ! -e "$APP" ] && ! grep -qi "extension" "$LOGS/uninstall-no-tool.txt"'
check "and the settings are back to the original" 'json_equal "$WORKDIR/original.json" "$SETTINGS"'

echo "--- release tags, with curl stood in for (no network)"
DOWNLOADS="$WORKDIR/downloads"
mkdir -p "$DOWNLOADS/bin"
cat >"$DOWNLOADS/bin/curl" <<'STUB'
#!/bin/bash
set -euo pipefail
out="" url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >>"$DOWNLOAD_LOG"
if [ "$url" = "https://api.github.com/repos/robertodf99/fde-toolkit/releases/latest" ]; then
  printf '{"tag_name":"%s"}\n' "$DOWNLOAD_LATEST"
  exit 0
fi
base="https://github.com/robertodf99/fde-toolkit/releases/download/$DOWNLOAD_TAG/hook-me-up-$DOWNLOAD_VERSION-macos.zip"
case "$url" in
  "$base") cp "$DOWNLOAD_ZIP" "$out" ;;
  "$base.sha256")
    if [ "${DOWNLOAD_BAD_CHECKSUM:-0}" = 1 ]; then printf 'bad checksum\n' >"$out"; else cp "$DOWNLOAD_ZIP.sha256" "$out"; fi
    ;;
  *) printf 'curl: (22) HTTP 404 for %s\n' "$url" >&2; exit 22 ;;
esac
STUB
chmod +x "$DOWNLOADS/bin/curl"
download_run() { # name, requested version (empty = latest), available tag, extra env...
  local name="$1" requested="$2" available="$3"
  shift 3
  : >"$LOGS/download-$name.urls"
  run install.sh HOOK_ME_UP_ZIP= HOOK_ME_UP_YES=1 HOOK_ME_UP_VERSION="$requested" \
    PATH="$DOWNLOADS/bin:$SAFE_PATH" DOWNLOAD_LOG="$LOGS/download-$name.urls" \
    DOWNLOAD_ZIP="$ZIP" DOWNLOAD_TAG="$available" DOWNLOAD_VERSION=0.5.0-rc.1 DOWNLOAD_LATEST="$available" \
    "$@" >"$LOGS/download-$name.txt" 2>&1
}
NEW_BASE="https://github.com/robertodf99/fde-toolkit/releases/download/hook-me-up-v0.5.0-rc.1/hook-me-up-0.5.0-rc.1-macos.zip"
OLD_BASE="https://github.com/robertodf99/fde-toolkit/releases/download/v0.5.0-rc.1/hook-me-up-0.5.0-rc.1-macos.zip"
for requested in 0.5.0-rc.1 v0.5.0-rc.1 hook-me-up-v0.5.0-rc.1; do
  if download_run "$requested" "$requested" hook-me-up-v0.5.0-rc.1; then status=0; else status=$?; fi
  check "$requested: the new tag installs, with unchanged asset names" \
    '[ "$status" = 0 ] && [ -x "$APP/Contents/MacOS/hook-me-up" ] && \
     [ "$(cat "$LOGS/download-$requested.urls")" = "$(printf "%s\n%s" "$NEW_BASE" "$NEW_BASE.sha256")" ]'
done
if download_run legacy v0.5.0-rc.1 v0.5.0-rc.1; then status=0; else status=$?; fi
check "an explicit version tries the new tag, then the legacy tag" \
  '[ "$status" = 0 ] && [ "$(cat "$LOGS/download-legacy.urls")" = "$(printf "%s\n%s\n%s" "$NEW_BASE" "$OLD_BASE" "$OLD_BASE.sha256")" ]'
check "a successful legacy fallback hides the first download's 404" \
  '! grep -q "curl: (22)" "$LOGS/download-legacy.txt"'
for available in hook-me-up-v0.5.0-rc.1 v0.5.0-rc.1; do
  if download_run "latest-$available" "" "$available"; then status=0; else status=$?; fi
  check "latest $available installs from the tag returned by the API" \
    '[ "$status" = 0 ] && [ "$(wc -l <"$LOGS/download-latest-$available.urls" | tr -d " ")" = 3 ]'
done
DOWNLOAD_STATE="$(tree_state)"
for available in agent-workflow-v1.0.0 hook-me-up-v vunknown; do
  if download_run "reject-$available" "" "$available"; then status=0; else status=$?; fi
  check "latest $available is rejected before any asset is downloaded" \
    '[ "$status" != 0 ] && [ "$(wc -l <"$LOGS/download-reject-$available.urls" | tr -d " ")" = 1 ] && same_tree "$DOWNLOAD_STATE"'
done
for requested in hook-me-up-vv0.5.0-rc.1 agent-workflow-v1.0.0 '../0.5.0'; do
  if download_run invalid "$requested" missing; then status=0; else status=$?; fi
  check "invalid explicit version $requested is rejected before downloading" \
    '[ "$status" != 0 ] && [ ! -s "$LOGS/download-invalid.urls" ] && same_tree "$DOWNLOAD_STATE"'
done
if download_run missing 0.5.0-rc.1 missing; then status=0; else status=$?; fi
check "both tags missing: fails without changing the installation" \
  '[ "$status" != 0 ] && [ "$(cat "$LOGS/download-missing.urls")" = "$(printf "%s\n%s" "$NEW_BASE" "$OLD_BASE")" ] && same_tree "$DOWNLOAD_STATE"'
check "only the last failed download's curl error stays visible" \
  'grep -qF "curl: (22) HTTP 404 for $OLD_BASE" "$LOGS/download-missing.txt" && \
   ! grep -qF "curl: (22) HTTP 404 for $NEW_BASE" "$LOGS/download-missing.txt"'
if download_run latest-missing "" hook-me-up-v0.5.0-rc.1 DOWNLOAD_TAG=missing; then status=0; else status=$?; fi
check "a latest release without fallback still shows its curl error" \
  '[ "$status" != 0 ] && grep -qF "curl: (22) HTTP 404 for $NEW_BASE" "$LOGS/download-latest-missing.txt" && same_tree "$DOWNLOAD_STATE"'
if download_run checksum 0.5.0-rc.1 hook-me-up-v0.5.0-rc.1 DOWNLOAD_BAD_CHECKSUM=1; then status=0; else status=$?; fi
check "a wrong checksum fails without fallback or installation changes" \
  '[ "$status" != 0 ] && grep -q "checksum mismatch" "$LOGS/download-checksum.txt" && \
   [ "$(wc -l <"$LOGS/download-checksum.urls" | tr -d " ")" = 2 ] && same_tree "$DOWNLOAD_STATE"'
run uninstall.sh HOOK_ME_UP_YES=1 >"$LOGS/uninstall-download.txt" 2>&1
check "downloaded package uninstalls and restores the original settings" \
  'json_equal "$WORKDIR/original.json" "$SETTINGS" && [ ! -e "$APP" ]'

check "the real HOME was not touched" '[ "$BEFORE" = "$(fingerprint)" ]'

if [ "$failures" -ne 0 ]; then
  echo "test-install: $failures failed; logs:"
  tail -n 15 "$LOGS"/*.txt
  exit 1
fi
echo "test-install: all checks passed"
