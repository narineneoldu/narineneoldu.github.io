#!/bin/bash
set -e

# Go up two levels from this script's directory to reach the project root
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "[sync-en] Copying en/_site into tr/_site/en/ ..."

TARGET_DIR="$ROOT_DIR/tr/_site/en"

# Clean target and recreate
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Copy en/_site content into tr/_site/en/
if [ -d "$ROOT_DIR/en/_site" ]; then
  cp -R "$ROOT_DIR/en/_site/"* "$TARGET_DIR/"
  echo "[sync-en] Done."
else
  echo "[sync-en] ERROR: $ROOT_DIR/en/_site does not exist. Did you run 'quarto render en'?"
  exit 1
fi
