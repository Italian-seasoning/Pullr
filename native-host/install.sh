#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="app.pullr.native"
EXTENSION_ID="${1:-eoinkcmbnjeogalchfalgfjbahbfiokj}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_SCRIPT="$ROOT_DIR/native-host/pullr_native_host.py"
HOST_DIRS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/Comet/NativeMessagingHosts"
)

chmod +x "$HOST_SCRIPT"
for host_dir in "${HOST_DIRS[@]}"; do
  host_manifest="$host_dir/$HOST_NAME.json"
  mkdir -p "$host_dir"
  cat >"$host_manifest" <<JSON
{
  "name": "$HOST_NAME",
  "description": "Pullr native messaging host",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
JSON
  echo "$host_manifest"
done
