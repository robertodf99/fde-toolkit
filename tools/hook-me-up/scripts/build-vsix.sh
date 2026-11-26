#!/bin/bash
# Packs the editor extension (editor-extension/) as a VSIX, by hand: a zip holding
# [Content_Types].xml, extension.vsixmanifest and the extension under extension/
# (package.json, extension.js, README.md, LICENSE.txt). No npm and no vsce: the extension
# is plain JavaScript with no dependencies and no build step. VS Code, VS Code Insiders,
# Cursor and Windsurf install it with `<cli> --install-extension <file> --force`.
# scripts/build-app.sh puts it in the app as Contents/Resources/hook-me-up.vsix.
#
# Usage: scripts/build-vsix.sh <output.vsix>
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-}"
case "$OUT" in
  *.vsix) ;;
  *)
    echo "usage: scripts/build-vsix.sh <output.vsix>" >&2
    exit 2
    ;;
esac
SRC=editor-extension
die() {
  echo "build-vsix: $*" >&2
  exit 1
}
# plutil reads JSON too; a package.json that isn't valid JSON stops the build here.
field() { plutil -extract "$1" raw -o - "$SRC/package.json" 2>/dev/null || die "$SRC/package.json has no $1"; }
publisher="$(field publisher)"
name="$(field name)"
version="$(field version)"
display="$(field displayName)"
description="$(field description)"
engine="$(field engines.vscode)"
kind="$(field extensionKind.0)"
[ "$publisher.$name" = "hook-me-up.hook-me-up" ] || die "the extension must be hook-me-up.hook-me-up"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version [$version]"
[ "$(field main)" = "./extension.js" ] || die "main must be ./extension.js"
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hmu-vsix.XXXXXX")"
case "$STAGE" in
  */hmu-vsix.*) ;;
  *) die "unexpected temporary folder [$STAGE]" ;;
esac
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/extension"
cp "$SRC/package.json" "$SRC/extension.js" "$SRC/README.md" "$STAGE/extension/"
cp "$SRC/LICENSE" "$STAGE/extension/LICENSE.txt"

cat >"$STAGE/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".md" ContentType="text/markdown"/>
  <Default Extension=".txt" ContentType="text/plain"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
EOF

cat >"$STAGE/extension.vsixmanifest" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="$(xml "$name")" Version="$(xml "$version")" Publisher="$(xml "$publisher")"/>
    <DisplayName>$(xml "$display")</DisplayName>
    <Description xml:space="preserve">$(xml "$description")</Description>
    <Tags></Tags>
    <Categories>Other</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="$(xml "$engine")"/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionDependencies" Value=""/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionPack" Value=""/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="$(xml "$kind")"/>
      <Property Id="Microsoft.VisualStudio.Code.LocalizedLanguages" Value=""/>
      <Property Id="Microsoft.VisualStudio.Services.Links.Source" Value="https://github.com/robertodf99/fde-toolkit"/>
    </Properties>
    <License>extension/LICENSE.txt</License>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
    <Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true"/>
    <Asset Type="Microsoft.VisualStudio.Services.Content.License" Path="extension/LICENSE.txt" Addressable="true"/>
  </Assets>
</PackageManifest>
EOF

# Fixed times and no extra attributes or folder entries: the same sources give the same bytes.
find "$STAGE" -exec touch -h -t 202601010000 {} +
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT"
# -nw: names are literal ([Content_Types].xml would otherwise be a wildcard).
(cd "$STAGE" && zip -q -X -D -nw "$OUT" "[Content_Types].xml" extension.vsixmanifest \
  extension/package.json extension/extension.js extension/README.md extension/LICENSE.txt)
echo "Built $OUT ($publisher.$name $version)"
