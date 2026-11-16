#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/Sparkle.framework"
SOURCE="${1:-$DEST}"
IDENTITY="${SIGN_IDENTITY:--}"

if [[ ! -d "$SOURCE" ]]; then
  echo "ERROR: Sparkle.framework not found at: $SOURCE" >&2
  echo "Usage: $0 [path/to/Sparkle.framework]" >&2
  exit 1
fi

if [[ "$SOURCE" != "$DEST" ]]; then
  echo "Staging Sparkle.framework from: $SOURCE"
  /usr/bin/ditto "$SOURCE" "$DEST"
fi

EXECUTABLE="$DEST/Versions/Current/Sparkle"
AUTUPDATE="$DEST/Versions/Current/Autoupdate"
MODULEMAP="$DEST/Modules/module.modulemap"

for required in "$EXECUTABLE" "$AUTUPDATE" "$MODULEMAP" \
  "$DEST/Versions/Current/Updater.app/Contents/Info.plist" \
  "$DEST/Versions/Current/XPCServices/Downloader.xpc/Contents/Info.plist" \
  "$DEST/Versions/Current/XPCServices/Installer.xpc/Contents/Info.plist"; do
  if [[ ! -e "$required" ]]; then
    echo "ERROR: Incomplete Sparkle.framework; missing: $required" >&2
    exit 1
  fi
done

if ! /usr/bin/lipo -archs "$EXECUTABLE" | tr ' ' '\n' | grep -qx arm64; then
  echo "ERROR: Sparkle.framework does not contain an arm64 slice." >&2
  exit 1
fi

# A standalone Autoupdate.app is not required by this Sparkle bundle layout.
# Autoupdate is the helper executable; Xcode embeds the complete framework.
echo "Signing Sparkle.framework with identity: $IDENTITY"
/usr/bin/codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$DEST"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DEST"

printf '\nSparkle framework verified. arm64 slice: '
/usr/bin/lipo -archs "$EXECUTABLE"
printf 'Updater helper: %s\n' "$DEST/Versions/Current/Updater.app"
printf 'Autoupdate executable: %s\n' "$AUTUPDATE"
