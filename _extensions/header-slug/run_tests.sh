#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${NO_COLOR:-}" || "$TERM" == "dumb" || -n "${CI:-}" ]]; then
  SUCCESS=''
  FAIL=''
  RESET=''
else
  SUCCESS='\033[1;35m'
  FAIL='\033[1;31m'
  RESET='\033[0m'
fi

# Resolve directory of this script, regardless of current working directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
EXT_ROOT="$SCRIPT_DIR"
TESTS_DIR="$EXT_ROOT/tests"

echo "Running Lua tests from: $TESTS_DIR"
cd "$TESTS_DIR"

# Run all test_*.lua files (stable ordering)
echo
fail=0
for f in $(ls -1 test_*.lua 2>/dev/null | sort); do
  echo -n "▶ lua $f "
  lua "$f" || fail=1
done

if [[ "$fail" -ne 0 ]]; then
  echo
  echo -e "${FAIL}✘ Some tests failed.${RESET}"
  exit 1
fi

echo
echo -e "${SUCCESS}✔ All tests completed successfully.${RESET}"
