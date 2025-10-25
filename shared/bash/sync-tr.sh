#!/bin/bash
set -e

# Go up two levels from this script's directory to reach the project root
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
EN_SRC="$ROOT_DIR/en/_site"
EN_TARGET="$ROOT_DIR/tr/_site/en"

echo "[sync-tr] Starting combined sync (TR + EN)..."

# Step 1: If English _site exists, copy it into tr/_site/en/
if [ -d "$EN_SRC" ]; then
  echo "[sync-tr] Copying en/_site into tr/_site/en ..."
  rm -rf "$EN_TARGET"
  mkdir -p "$EN_TARGET"
  cp -R "$EN_SRC/"* "$EN_TARGET/"
  echo "[sync-tr] English content copied."
else
  echo "[sync-tr] WARNING: en/_site not found. Skipping English content."
fi

# Step 2: Deploy tr/_site into docs/
echo "[sync-tr] Deploying tr/_site into docs/ ..."
rm -rf "$DOCS_DIR"
mkdir -p "$DOCS_DIR"

if [ -d "$ROOT_DIR/tr/_site" ]; then
  cp -R "$ROOT_DIR/tr/_site/"* "$DOCS_DIR/"
  echo "[sync-tr] Deployment complete. ✅"
else
  echo "[sync-tr] ERROR: tr/_site does not exist. Did you run 'quarto render tr'?"
  exit 1
fi
