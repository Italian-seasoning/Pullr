#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.1.3}"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/Pullr}"
TAG="v$VERSION"
RELEASE_DIR="$ROOT/dist/github-release/$TAG"
ARCHIVE_NAME="Pullr-$VERSION-macOS.zip"
DMG_NAME="Pullr-$VERSION-macOS.dmg"
BROWSER_NAME="Pullr-$VERSION-Browser-Extension.zip"
SPARKLE_BIN="${SPARKLE_BIN_OVERRIDE:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
REUSE_APP="${PULLR_REUSE_APP:-0}"
if [[ "$REUSE_APP" == "1" ]]; then
  echo "Build from source for releases; reusing an app can publish stale code or build numbers." >&2
  exit 1
fi

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
  PULLR_CONFIGURATION=release PULLR_ARCHITECTURE=universal PULLR_VERSION="$VERSION" "$ROOT/script/build_and_run.sh" --package
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

BROWSER_STAGE="$RELEASE_DIR/Pullr-Browser-Extension"
mkdir -p "$BROWSER_STAGE/chrome-extension" "$BROWSER_STAGE/native-host"
for file in "$ROOT"/chrome-extension/*; do
  [[ -f "$file" && "$(basename "$file")" != test_* ]] || continue
  cp "$file" "$BROWSER_STAGE/chrome-extension/"
done
ditto "$ROOT/chrome-extension/icons" "$BROWSER_STAGE/chrome-extension/icons"
cp "$ROOT/native-host/install.sh" "$ROOT/native-host/pullr_native_host.py" "$BROWSER_STAGE/native-host/"
cp "$ROOT/PRIVACY.md" "$ROOT/TERMS.md" "$BROWSER_STAGE/"
cat >"$BROWSER_STAGE/README.txt" <<'INSTRUCTIONS'
Pullr browser extension

Keep this extracted folder in a permanent location. In Chrome's Extensions page,
enable Developer mode and load the chrome-extension folder. From a Terminal in
this folder, run ./native-host/install.sh to connect the native helper. If updating
an existing unpacked extension, replace its files, reload it in Chrome, and
refresh any open YouTube tabs. See chrome-extension/README.md for details.
INSTRUCTIONS
ditto -c -k --norsrc --keepParent "$BROWSER_STAGE" "$RELEASE_DIR/$BROWSER_NAME"
rm -rf "$BROWSER_STAGE"

APPCAST_STAGE="$RELEASE_DIR/appcast-source"
mkdir -p "$APPCAST_STAGE"
ditto "$RELEASE_DIR/$DMG_NAME" "$APPCAST_STAGE/$DMG_NAME"
cat >"$APPCAST_STAGE/Pullr-$VERSION-macOS.md" <<NOTES
Pullr $VERSION improves download reliability, queue recovery, and background efficiency. YouTube videos can be saved as H.265, and Apple Music matching better distinguishes similar titles.

To update the browser extension and native helper, download the separate Browser Extension archive and follow its README. The app updater does not replace those components.

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
python3 "$ROOT/script/verify_update.py" "$APP" "$RELEASE_DIR/$DMG_NAME" "$RELEASE_DIR/appcast.xml" --sparkle-bin "$SPARKLE_BIN" --repository "$REPOSITORY" --require-newer
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE_NAME" "$DMG_NAME" "$BROWSER_NAME" appcast.xml > SHA256SUMS.txt)

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
  "$RELEASE_DIR/$BROWSER_NAME" \
  "$RELEASE_DIR/appcast.xml" \
  "$RELEASE_DIR/SHA256SUMS.txt"
