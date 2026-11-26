#!/bin/bash
# Checks the signing choices of scripts/build-app.sh:
#   1. CODESIGN_IDENTITY=- forces an ad-hoc signature;
#   2. with no identities in the keychain (simulated) it falls back to ad-hoc;
#   3. the normal auto-pick signs the app and the hook alike.
# Every bundle is built in a private temporary folder (APP_DIR), so an app already
# built or running from .build/HookMeUp.app is never replaced; the last check
# verifies that. Only the files this script created are removed.
set -u
cd "$(dirname "$0")/.."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hmu-signing.XXXXXX")" || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "signing-check: no temporary folder" >&2; exit 1; }
OUT="$WORK/out"
mkdir "$OUT" || exit 1
cleanup() {
  rm -rf "$WORK/out/HookMeUp.app"
  rm -f "$WORK/security"
  rmdir "$WORK/out" "$WORK" 2>/dev/null
}
trap cleanup EXIT

FAKE_SECURITY="$WORK/security"
printf '#!/bin/sh\necho "     0 valid identities found"\n' > "$FAKE_SECURITY"
chmod +x "$FAKE_SECURITY"

# The bundle in .build (maybe running) must not change.
stamp() {
  if [ -e "$1" ]; then stat -f '%i %m' "$1" "$1/Contents/MacOS/HookMeUp" 2>/dev/null | tr '\n' ' '; else echo "absent"; fi
}
before="$(stamp .build/HookMeUp.app)"

failures=0
signature() { codesign -dv "$1" 2>&1 | awk -F= '/^Signature=/ {print $2}'; }
team() { codesign -dv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2}'; }
expect_adhoc() {
  local name="$1" app hook
  app="$(signature "$OUT/HookMeUp.app")"
  hook="$(signature "$OUT/HookMeUp.app/Contents/MacOS/hook-me-up")"
  if [ "$app" = "adhoc" ] && [ "$hook" = "adhoc" ]; then
    echo "PASS  $name: app and hook ad-hoc"
  else
    echo "FAIL  $name: app=[$app] hook=[$hook]"
    failures=$((failures + 1))
  fi
}

APP_DIR="$OUT" CODESIGN_IDENTITY=- ./scripts/build-app.sh 2>&1 | grep -E '^Signing|^Built'
expect_adhoc "forced ad-hoc (CODESIGN_IDENTITY=-)"

env -u CODESIGN_IDENTITY APP_DIR="$OUT" SECURITY_BIN="$FAKE_SECURITY" ./scripts/build-app.sh 2>&1 | grep -E '^Signing|^Built'
expect_adhoc "no identities in the keychain"

env -u CODESIGN_IDENTITY APP_DIR="$OUT" ./scripts/build-app.sh 2>&1 | grep -E '^Signing|^Built'
app_team="$(team "$OUT/HookMeUp.app")"
hook_team="$(team "$OUT/HookMeUp.app/Contents/MacOS/hook-me-up")"
if [ "$app_team" = "$hook_team" ]; then
  echo "PASS  auto-pick: app and hook signed alike (TeamIdentifier=$app_team)"
else
  echo "FAIL  auto-pick: app team [$app_team] differs from hook team [$hook_team]"
  failures=$((failures + 1))
fi

after="$(stamp .build/HookMeUp.app)"
if [ "$before" = "$after" ]; then
  echo "PASS  .build/HookMeUp.app untouched ($after)"
else
  echo "FAIL  .build/HookMeUp.app changed: [$before] -> [$after]"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] && echo "signing-check: all checks passed" || { echo "signing-check: $failures failed"; exit 1; }
