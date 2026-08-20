#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: verify_release_privacy.sh <app-or-directory>}"

if find "$TARGET" \( -name .git -o -name .codex -o -name .DS_Store -o -name '*.dSYM' -o -name '*.pyc' -o -name embedded.provisionprofile \) -print -quit | grep -q .; then
  echo "Release contains a local-only project artifact." >&2
  exit 1
fi

if rg -a -l '/Users/[^/[:space:]]+' "$TARGET" | grep -q .; then
  echo "Release contains an absolute user path." >&2
  exit 1
fi

echo "Release privacy scan passed."
