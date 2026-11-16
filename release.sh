#!/bin/bash
#
# Builds a Release copy of Morph, zips + EdDSA-signs it for Sparkle, and adds
# the new version to ./appcast.xml.
#
# Usage:   ./release.sh <version> <build-number> ["release notes"]
# Example: ./release.sh 1.7.1 117 "Fixed the updater. New iOS-style volume HUD."
#
# Afterwards upload, on GitHub (guccmanegu-eng/getmorph.store):
#   releases/Morph-<version>.zip  ->  public/downloads/
#   appcast.xml                   ->  public/appcast.xml
# Vercel redeploys and every Morph install sees the update.

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version> <build-number> [\"release notes\"]}"
BUILD="${2:?Usage: ./release.sh <version> <build-number> [\"release notes\"]}"
NOTES="${3:-Bug fixes and improvements.}"

APP_NAME="Morph"
SCHEME="DynamicNotch"
PROJECT="Morph.xcodeproj"
SITE="https://www.getmorph.shop"
OUTPUT_DIR="./releases"
DERIVED="./build/DerivedData"
SIGN_TOOL="./bin/sign_update"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"
APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"

[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "❌ Build number must be an integer"; exit 1; }
LAST_BUILD=$(grep -o '<sparkle:version>[0-9]*' appcast.xml | grep -o '[0-9]*' | sort -n | tail -1 || echo 0)
if (( BUILD <= ${LAST_BUILD:-0} )); then
    echo "❌ Build ${BUILD} must be higher than the newest build in appcast.xml (${LAST_BUILD}), or Sparkle won't offer it."
    exit 1
fi
[[ -x "$SIGN_TOOL" ]] || { echo "❌ Sparkle sign_update not found at $SIGN_TOOL"; exit 1; }

echo "🔢 Setting version ${VERSION} (${BUILD}) in the Xcode project…"
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/; s/CURRENT_PROJECT_VERSION = 1[0-9]{2,};/CURRENT_PROJECT_VERSION = ${BUILD};/" "${PROJECT}/project.pbxproj"

echo "🛠  Building Release…"
rm -rf "${DERIVED}/Build/Products/Release/${APP_NAME}.app"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    clean build -quiet
[[ -d "$APP_PATH" ]] || { echo "❌ Build product not found at $APP_PATH"; exit 1; }

# --- Sanity checks: catch the mistakes that break Sparkle -------------------
PLIST="${APP_PATH}/Contents/Info.plist"
KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST")
KEY_BYTES=$(printf '%s' "$KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')
if [[ "$KEY_BYTES" != "32" || $(( ${#KEY} % 4 )) != 0 ]]; then
    echo "❌ SUPublicEDKey '$KEY' is not valid base64 for a 32-byte key (needs its '=' padding). Sparkle would fail to start."
    exit 1
fi
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST")
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
[[ "$BUILT_VERSION" == "$BUILD" ]] || { echo "❌ Built app has build $BUILT_VERSION, expected $BUILD"; exit 1; }
if [[ -e "${APP_PATH}/Contents/MacOS/${APP_NAME}.debug.dylib" ]]; then
    echo "❌ This is a Debug build (has ${APP_NAME}.debug.dylib)."; exit 1
fi
codesign --verify --deep --strict "$APP_PATH" || { echo "❌ App code signature is invalid"; exit 1; }
echo "✅ Feed: $FEED · key OK · build $BUILT_VERSION"

echo "📦 Zipping…"
mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "🔐 Signing…"
SIG_ATTRS=$("$SIGN_TOOL" "$ZIP_PATH")      # -> sparkle:edSignature="…" length="…"
[[ "$SIG_ATTRS" == *edSignature* ]] || { echo "❌ sign_update failed: $SIG_ATTRS"; exit 1; }

echo "📝 Adding ${VERSION} to appcast.xml…"
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
ITEM=$(cat <<ITEM
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[<p>${NOTES}</p>]]></description>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${SITE}/downloads/${ZIP_NAME}"
                ${SIG_ATTRS}
                type="application/octet-stream" />
        </item>
ITEM
)
python3 - "$ITEM" <<'PY'
import sys
item = sys.argv[1]
s = open("appcast.xml").read()
marker = "<!-- NEW-ITEMS -->"
assert marker in s, "appcast.xml is missing the <!-- NEW-ITEMS --> marker"
open("appcast.xml", "w").write(s.replace(marker, marker + "\n" + item, 1))
PY
xmllint --noout appcast.xml 2>/dev/null || plutil -lint appcast.xml >/dev/null 2>&1 || true

echo ""
echo "🎉 Done: ${ZIP_PATH}"
echo ""
echo "Upload to github.com/guccmanegu-eng/getmorph.store:"
echo "  1. ${ZIP_PATH}  →  public/downloads/${ZIP_NAME}"
echo "  2. ./appcast.xml        →  public/appcast.xml"
