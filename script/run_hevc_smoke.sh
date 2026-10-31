#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/hevc-smoke"
mkdir -p "$BUILD_DIR"
swiftc \
  "$ROOT_DIR/Sources/Pullr/Models/AppSettings.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/DownloadStatus.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/ExportPreset.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/PlaylistOptions.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/CommandBuilder.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/URLExtractor.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/YTDLPService.swift" \
  "$ROOT_DIR/Tests/HEVCSmoke/main.swift" \
  -o "$BUILD_DIR/HEVCSmoke"
"$BUILD_DIR/HEVCSmoke"
