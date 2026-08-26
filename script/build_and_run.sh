#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Pullr"
BUNDLE_ID="app.pullr.Pullr"
MIN_SYSTEM_VERSION="14.0"
VERSION="${PULLR_VERSION:-1.1.0}"
BUILD_NUMBER="${PULLR_BUILD_NUMBER:-1}"
CONFIGURATION="${PULLR_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

BUILD_ARGUMENTS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" ]]; then
  BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
  BUILD_ARGUMENTS+=(-Xswiftc -no-serialize-debugging-options)
  BUILD_ARGUMENTS+=(-Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=.")
  BUILD_ARGUMENTS+=(-Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=.")
fi
swift build "${BUILD_ARGUMENTS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ "$CONFIGURATION" == "release" ]]; then
  strip -x "$APP_BINARY"
fi
ditto "$BUILD_DIR/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BINARY"

if [[ -f "$ROOT_DIR/Sources/Pullr/Resources/PullrDark.icns" ]]; then
  cp "$ROOT_DIR/Sources/Pullr/Resources/PullrDark.icns" "$APP_RESOURCES/Pullr.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Pullr.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Pullr downloads only content you own, have permission to download, or that is legally available offline.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Pullr imports audio you download into your Music library.</string>
  <key>SUFeedURL</key>
  <string>https://github.com/Italian-seasoning/Pullr/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>8gXd94Dt3KOimiwIe/qd1fITXQDnKh94s0juVSOjXOI=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>pullr</string>
      </array>
    </dict>
  </array>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_FRAMEWORKS/Sparkle.framework"
codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
