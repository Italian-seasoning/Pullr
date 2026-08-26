#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.1.0}"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/Pullr}"
TAG="v$VERSION"
RELEASE_DIR="$ROOT/dist/github-release"
ARCHIVE_NAME="Pullr-$VERSION-macOS.zip"
DMG_NAME="Pullr-$VERSION-macOS.dmg"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
REUSE_APP="${PULLR_REUSE_APP:-0}"

command -v gh >/dev/null || { echo "GitHub CLI is required." >&2; exit 1; }
gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1 && { echo "$TAG already exists." >&2; exit 1; }

if [[ "$REUSE_APP" == "1" ]]; then
  APP_SOURCE="${PULLR_APP_PATH:-$ROOT/dist/Pullr.app}"
  [[ -d "$APP_SOURCE" ]] || { echo "Existing app not found: $APP_SOURCE" >&2; exit 1; }
  APP="$ROOT/dist/Pullr-$VERSION.app"
  rm -rf "$APP"
  ditto "$APP_SOURCE" "$APP"
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
else
  PULLR_CONFIGURATION=release PULLR_VERSION="$VERSION" "$ROOT/script/build_and_run.sh" --package
  APP="$ROOT/dist/Pullr.app"
fi

while IFS= read -r -d '' file; do
  if file "$file" | grep -q 'Mach-O'; then
    codesign --remove-signature "$file" >/dev/null 2>&1 || true
    strip -x "$file" >/dev/null 2>&1 || true
  fi
done < <(find "$APP" -type f -print0)
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
"$ROOT/script/verify_release_privacy.sh" "$APP"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
ditto -c -k --norsrc --keepParent "$APP" "$RELEASE_DIR/$ARCHIVE_NAME"
DMG_STAGE="$RELEASE_DIR/dmg-root"
mkdir -p "$DMG_STAGE"
ditto "$APP" "$DMG_STAGE/Pullr.app"
cp "$ROOT/script/install_pullr.command" "$DMG_STAGE/Install Pullr.command"
chmod +x "$DMG_STAGE/Install Pullr.command"
hdiutil create -quiet -volname "Pullr $VERSION" -srcfolder "$DMG_STAGE" -ov -format UDZO "$RELEASE_DIR/$DMG_NAME"
rm -rf "$DMG_STAGE"

APPCAST_STAGE="$RELEASE_DIR/appcast-source"
mkdir -p "$APPCAST_STAGE"
ditto "$RELEASE_DIR/$DMG_NAME" "$APPCAST_STAGE/$DMG_NAME"
cat >"$APPCAST_STAGE/Pullr-$VERSION-macOS.md" <<NOTES
Pullr $VERSION adds the new app icon, failed-download retry improvements, Homebrew-aware yt-dlp updates, Deno support for YouTube challenge handling, and optional local website and YouTube hours tracking.

The Chrome extension now includes the refreshed icon and an opt-in hours-tracking control. Activity stays on this Mac and can be cleared from Pullr.

This build is ad-hoc signed and not Apple-notarized. Control-click Pullr and choose Open on first launch.
NOTES

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  --link "https://github.com/$REPOSITORY" \
  --embed-release-notes \
  "$APPCAST_STAGE"
cp "$APPCAST_STAGE/appcast.xml" "$RELEASE_DIR/appcast.xml"
cp "$APPCAST_STAGE/Pullr-$VERSION-macOS.md" "$RELEASE_DIR/Pullr-$VERSION-macOS.md"
rm -rf "$APPCAST_STAGE"
xmllint --noout "$RELEASE_DIR/appcast.xml"
rg -q 'sparkle:edSignature=' "$RELEASE_DIR/appcast.xml"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE_NAME" "$DMG_NAME" appcast.xml > SHA256SUMS.txt)

if [[ "${PULLR_SKIP_PUBLISH:-0}" == "1" ]]; then
  echo "Package prepared at $RELEASE_DIR"
  exit 0
fi

gh release create "$TAG" \
  --repo "$REPOSITORY" \
  --target "$(git -C "$ROOT" rev-parse HEAD)" \
  --title "Pullr $VERSION preview" \
  --notes-file "$RELEASE_DIR/Pullr-$VERSION-macOS.md" \
  "$RELEASE_DIR/$ARCHIVE_NAME" \
  "$RELEASE_DIR/$DMG_NAME" \
  "$RELEASE_DIR/appcast.xml" \
  "$RELEASE_DIR/SHA256SUMS.txt"
