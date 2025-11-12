#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EN_SRC="$ROOT_DIR/en/_site"
TARGET_DIR="$ROOT_DIR/tr/_site/en"

echo "[sync-en] Syncing en/_site -> tr/_site/en ..."

if [[ -d "$EN_SRC" ]]; then
  mkdir -p "$TARGET_DIR"
  rsync -a --delete \
        --exclude '.DS_Store' \
        "$EN_SRC/" "$TARGET_DIR/" > /dev/null
  echo "[sync-en] Done."
else
  echo "[sync-en] ERROR: $EN_SRC does not exist. Did you run 'quarto render en'?"
  exit 1
fi
