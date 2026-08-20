#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
REPOSITORY="${GITHUB_REPOSITORY:-Italian-seasoning/Pullr}"
TAG="v$VERSION"
RELEASE_DIR="$ROOT/dist/github-release"
ARCHIVE_NAME="Pullr-$VERSION-macOS.zip"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

command -v gh >/dev/null || { echo "GitHub CLI is required." >&2; exit 1; }
gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1 && { echo "$TAG already exists." >&2; exit 1; }

PULLR_CONFIGURATION=release PULLR_VERSION="$VERSION" "$ROOT/script/build_and_run.sh" --package
APP="$ROOT/dist/Pullr.app"

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
cat >"$RELEASE_DIR/Pullr-$VERSION-macOS.md" <<NOTES
Pullr $VERSION is the first public preview with persistent privacy-safe diagnostics, Chrome and Apple Music integration, and Sparkle updates.

This build is ad-hoc signed and not Apple-notarized. Control-click Pullr and choose Open on first launch.
NOTES

"$SPARKLE_BIN/generate_appcast" \
  --account Pullr \
  --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
  --link "https://github.com/$REPOSITORY" \
  "$RELEASE_DIR"
xmllint --noout "$RELEASE_DIR/appcast.xml"
rg -q 'sparkle:edSignature=' "$RELEASE_DIR/appcast.xml"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE_NAME" appcast.xml > SHA256SUMS.txt)

gh release create "$TAG" \
  --repo "$REPOSITORY" \
  --target "$(git -C "$ROOT" rev-parse HEAD)" \
  --title "Pullr $VERSION preview" \
  --notes-file "$RELEASE_DIR/Pullr-$VERSION-macOS.md" \
  "$RELEASE_DIR/$ARCHIVE_NAME" \
  "$RELEASE_DIR/appcast.xml" \
  "$RELEASE_DIR/SHA256SUMS.txt"
