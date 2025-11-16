#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
TR_SRC="$ROOT_DIR/tr/_site"

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
