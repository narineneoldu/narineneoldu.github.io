#!/usr/bin/env bash
set -euo pipefail

# CI-friendly defaults; override in workflow if needed.
PERF_TOKENS="${PERF_TOKENS:-20000}"
PERF_MAX_SECONDS="${PERF_MAX_SECONDS:-0.05}"  # tune after observing CI baseline

out="$(PERF_TOKENS="$PERF_TOKENS" lua tests/perf_scan.lua)"
echo "$out"

elapsed="$(echo "$out" | sed -n 's/.*elapsed=\([0-9.]*\)s.*/\1/p')"

# If parsing fails, do not fail the build; just warn.
if [[ -z "${elapsed}" ]]; then
  echo "perf_guard: WARN could not parse elapsed seconds"
  exit 0
fi

# Compare float with awk.
is_slow="$(awk -v e="$elapsed" -v m="$PERF_MAX_SECONDS" 'BEGIN{print (e>m) ? "1":"0"}')"

PERF_ENFORCE="${PERF_ENFORCE:-0}"
if [[ "$is_slow" == "1" ]]; then
  echo "perf_guard: WARN regression suspected (elapsed=${elapsed}s > max=${PERF_MAX_SECONDS}s)"
  if [[ "$PERF_ENFORCE" == "1" ]]; then
    echo "perf_guard: FAIL (enforced)"
    exit 1
  fi
  exit 0
fi

echo "perf_guard: OK elapsed=${elapsed}s <= ${PERF_MAX_SECONDS}s"
