#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/app-store-smoke"
mkdir -p "$BUILD_DIR"
SOURCES=()
while IFS= read -r -d '' source; do
  SOURCES+=("$source")
done < <(find "$ROOT_DIR/Sources/Pullr/Models" "$ROOT_DIR/Sources/Pullr/Stores" "$ROOT_DIR/Sources/Pullr/Services" -name '*.swift' ! -name AppUpdater.swift -print0)
swiftc -parse-as-library "${SOURCES[@]}" "$ROOT_DIR/Tests/AppStoreSmoke/main.swift" -o "$BUILD_DIR/AppStoreSmoke"
"$BUILD_DIR/AppStoreSmoke"
