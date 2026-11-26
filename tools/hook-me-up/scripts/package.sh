#!/bin/bash
# Packages a release: .build/dist/hook-me-up-<version>-macos.zip holding HookMeUp.app
# (whose Contents/MacOS also holds both CLIs, hook-me-up and hook-me-up-setup) and the
# zip's .sha256. VERSION defaults to "dev"; a leading "v" is dropped. Other settings
# (UNIVERSAL, CODESIGN_IDENTITY) go to scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-dev}"
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
  echo "package: invalid VERSION [$VERSION]" >&2
  exit 1
fi
NAME="hook-me-up-$VERSION-macos.zip"

mkdir -p .build/dist
APP_DIR=.build/dist APP_VERSION="$VERSION" ./scripts/build-app.sh
rm -f ".build/dist/$NAME" ".build/dist/$NAME.sha256"
(
  cd .build/dist
  # No resource forks, extended attributes or quarantine: no AppleDouble files.
  ditto -c -k --norsrc --noextattr --noqtn --keepParent HookMeUp.app "$NAME"
  shasum -a 256 "$NAME" > "$NAME.sha256"
)
echo "Packaged .build/dist/$NAME"
cat ".build/dist/$NAME.sha256"
