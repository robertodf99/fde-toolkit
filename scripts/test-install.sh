#!/bin/bash
# Runs install.sh and uninstall.sh against a throwaway HOME, the way `curl | bash` runs
# them (script on stdin), with a locally built package and without launchctl. Checks:
# the hooks are added (and only with consent), a second install changes nothing, a
# truncated download or a failed install leaves everything as it was, uninstall
# restores the original settings and leaves the backups, a declined uninstall leaves
# the agent installed, and the real HOME is never touched.
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
  env HOME="$FAKE" HOOK_ME_UP_ZIP="$ZIP" HOOK_ME_UP_DRY_LAUNCH=1 HOOK_ME_UP_NO_TTY=1 "$@" bash <"$script"
}
run_truncated() { # script, fraction of its lines to keep (e.g. 1/2)
  local lines
  lines="$(($(wc -l <"$1") * ${2%/*} / ${2#*/}))"
  head -n "$lines" "$1" | env HOME="$FAKE" HOOK_ME_UP_ZIP="$ZIP" HOOK_ME_UP_DRY_LAUNCH=1 HOOK_ME_UP_NO_TTY=1 \
    HOOK_ME_UP_YES=1 bash
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
if [ -d /Applications/Claude.app ] || [ -d "$FAKE/Applications/Claude.app" ]; then
  check "official Claude icon applied" 'grep -q "Icon: the official icon" "$LOGS/install-1.txt"'
fi
check "LaunchAgent written and valid" 'plutil -lint -s "$PLIST"'
check "support folder is private" '[ "$(stat -f %Lp "$FAKE/Library/Application Support/hook-me-up")" = 700 ]'
check "settings untouched without consent" 'cmp -s "$WORKDIR/original.json" "$SETTINGS"'
check "says how to add the hooks" 'grep -q "HOOK_ME_UP_YES=1" "$LOGS/install-1.txt"'

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

echo "--- install again (upgrade)"
run install.sh HOOK_ME_UP_YES=1 >"$LOGS/install-3.txt" 2>&1
check "second install leaves the settings as they were" 'cmp -s "$WORKDIR/after-install.json" "$SETTINGS"'
check "second install reports no changes" 'grep -q "No changes" "$LOGS/install-3.txt"'
check "app still installed" '[ -x "$APP/Contents/MacOS/HookMeUp" ]'
check "no staging folders left" '! ls -a "$FAKE/Applications" | grep -q "^\.Hook Me Up"'

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

check "the real HOME was not touched" '[ "$BEFORE" = "$(fingerprint)" ]'

if [ "$failures" -ne 0 ]; then
  echo "test-install: $failures failed; logs:"
  tail -n 15 "$LOGS"/*.txt
  exit 1
fi
echo "test-install: all checks passed"
