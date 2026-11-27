#!/bin/bash
# Builds $APP_DIR/HookMeUp.app (default .build): the agent and both CLIs (hook-me-up,
# hook-me-up-setup) in Contents/MacOS, the app icon and the editor extension
# (Contents/Resources/hook-me-up.vsix, see scripts/build-vsix.sh), signed. Writes only
# .build (the Swift build) and $APP_DIR, where it replaces only HookMeUp.app.
#
# UNIVERSAL=1 builds for arm64 and x86_64 (release builds); APP_VERSION sets the version.
#
# Signing identity, in order:
#   1. $CODESIGN_IDENTITY when set ("-" forces ad-hoc);
#   2. the first "Apple Development:" identity in the keychain (a stable signature keeps
#      macOS permissions such as Notifications and Automation across rebuilds);
#   3. ad-hoc ("-").
# The nested CLIs are signed with the same identity. No hardened runtime, no timestamp
# (local build). Only the identity's hash prefix is printed, never its name.
set -euo pipefail

cd "$(dirname "$0")/.."
# The xcode-select toolchain as is; Xcode's only when the Command Line Tools are selected,
# DEVELOPER_DIR is unset and Xcode is in /Applications (same rule as the Makefile).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ] \
  && xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SECURITY_BIN="${SECURITY_BIN:-/usr/bin/security}" # overridable for scripts/check-signing.sh

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
for product in HookMeUp hook-me-up hook-me-up-setup; do
  swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --product "$product"
done
BIN="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

IDENTITY="${CODESIGN_IDENTITY:-}"
SOURCE="CODESIGN_IDENTITY"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$("$SECURITY_BIN" find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / {print $2; exit}')"
  SOURCE="keychain (first Apple Development identity)"
fi
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  IDENTITY="-"
  echo "Signing: ad-hoc"
elif [[ "$IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
  echo "Signing: identity ${IDENTITY:0:8}… from $SOURCE"
else
  echo "Signing: identity from $SOURCE"
fi

# Fresh bundle each time. Only the two fixed names below are ever removed, inside a
# checked output folder.
APP_DIR="${APP_DIR:-.build}"
case "$APP_DIR" in
  "" | "/" | "." | "..") echo "build-app: refusing APP_DIR=[$APP_DIR]" >&2; exit 1 ;;
esac
mkdir -p "$APP_DIR"
[ -d "$APP_DIR" ] || { echo "build-app: $APP_DIR is not a folder" >&2; exit 1; }
APP="$APP_DIR/HookMeUp.app"
rm -rf "$APP_DIR/HookMeUp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# APP_VERSION (from scripts/package.sh) becomes the bundle's version: 1.2.0 as is; a
# prerelease such as 1.2.0-beta.1 gives CFBundleShortVersionString 1.2.0 and keeps the
# full string in CFBundleVersion.
if [[ "${APP_VERSION:-}" =~ ^([0-9]+(\.[0-9]+){0,2})(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BASH_REMATCH[1]}" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
fi
for executable in HookMeUp hook-me-up hook-me-up-setup; do
  cp "$BIN/$executable" "$APP/Contents/MacOS/$executable"
done

# Original app icon and separate, source-identifying client attachment images.
xcrun swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns"
xcrun swift scripts/make-client-symbols.swift Resources/icon "$APP/Contents/Resources"

# The editor extension, which install.sh adds to VS Code and the editors built on it.
./scripts/build-vsix.sh "$APP/Contents/Resources/hook-me-up.vsix"

# Inner executables first, then the bundle (which seals Contents/MacOS/HookMeUp and the
# resources, the extension among them).
codesign --force --sign "$IDENTITY" --timestamp=none --identifier io.github.robertodf99.hook-me-up.hook \
  "$APP/Contents/MacOS/hook-me-up"
codesign --force --sign "$IDENTITY" --timestamp=none --identifier io.github.robertodf99.hook-me-up.setup \
  "$APP/Contents/MacOS/hook-me-up-setup"
codesign --force --sign "$IDENTITY" --timestamp=none --identifier io.github.robertodf99.hook-me-up "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
