#!/bin/zsh
set -euo pipefail
umask 022

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/Pullr.app"
DESTINATION="/Applications/Pullr.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  print -u2 "Pullr.app must be next to this installer."
  exit 1
fi

if [[ -w "/Applications" ]]; then
  ditto --rsrc --extattr "$SOURCE_APP" "$DESTINATION"
else
  sudo ditto --rsrc --extattr "$SOURCE_APP" "$DESTINATION"
fi

open -a Pullr "$DESTINATION"
print "Pullr was installed to /Applications. You can close this window."
