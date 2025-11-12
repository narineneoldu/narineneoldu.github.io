#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
TR_SRC="$ROOT_DIR/tr/_site"
EN_SRC="$ROOT_DIR/en/_site"
EN_TARGET="$ROOT_DIR/tr/_site/en"

echo "[sync-tr] Starting combined sync (TR + EN)..."

# Step 1: Sync English
if [[ -d "$EN_SRC" ]]; then
  echo "[sync-tr] Syncing en/_site -> tr/_site/en ..."
  mkdir -p "$EN_TARGET"
  rsync -a --delete --exclude '.DS_Store' \
        "$EN_SRC/" "$EN_TARGET/" > /dev/null
  echo "[sync-tr] English content synced."
else
  echo "[sync-tr] WARNING: en/_site not found. Skipping English content."
fi

# Step 2: Deploy Turkish
echo "[sync-tr] Deploying tr/_site -> docs/ ..."
mkdir -p "$DOCS_DIR"
if [[ -d "$TR_SRC" ]]; then
  rsync -a --delete --exclude '.DS_Store' \
        "$TR_SRC/" "$DOCS_DIR/" > /dev/null
  echo "[sync-tr] Deployment complete. ✅"
else
  echo "[sync-tr] ERROR: tr/_site does not exist. Did you run 'quarto render tr'?"
  exit 1
fi
