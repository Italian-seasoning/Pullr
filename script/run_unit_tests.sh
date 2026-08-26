#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual-tests"
RUNNER="$BUILD_DIR/PullrUnitTests"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT_DIR/Sources/Pullr/Models/AppSettings.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/AppNavigation.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/DownloadItem.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/DownloadStatus.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/ExportPreset.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/HistoryItem.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/ListeningEvent.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/MediaDeskLayout.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/PlaylistOptions.swift" \
  "$ROOT_DIR/Sources/Pullr/Models/SeasonCapturePlan.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/CommandBuilder.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/BinaryUpdateService.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/DownloadQueueManager.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/MetadataService.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/MusicLibraryService.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/URLExtractor.swift" \
  "$ROOT_DIR/Sources/Pullr/Services/YTDLPService.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/PresetStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/QueueStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/DownloadLogStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/HistoryStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/ListeningHistoryStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/SeasonStore.swift" \
  "$ROOT_DIR/Sources/Pullr/Stores/StorageLocation.swift" \
  "$ROOT_DIR/Tests/PullrUnitTests/main.swift" \
  -o "$RUNNER"

"$RUNNER"
