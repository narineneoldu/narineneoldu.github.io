#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory (works regardless of where it's called from)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}/tests"

echo "Running Lua tests from: ${TESTS_DIR}"
echo

# Find and run all test_*.lua files, sorted for stable order
for test_file in $(find "${TESTS_DIR}" -maxdepth 1 -type f -name 'test_*.lua' | sort); do
  echo "▶ lua $(basename "${test_file}")"
  lua "${test_file}"
  echo
done

echo "✔ All tests completed successfully."
