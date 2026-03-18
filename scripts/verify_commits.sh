#!/usr/bin/env bash
set -euo pipefail

EXPECTED_COUNT="${EXPECTED_COUNT:-300}"
EXPECTED_NAME="${EXPECTED_NAME:-najnomics}"
EXPECTED_EMAIL="${EXPECTED_EMAIL:-jesuorobonosakhare873@gmail.com}"
STRICT_COMMIT_COUNT="${STRICT_COMMIT_COUNT:-1}"

actual_count="$(git rev-list --count HEAD)"
if [[ "$STRICT_COMMIT_COUNT" == "1" ]]; then
  if [[ "$actual_count" -ne "$EXPECTED_COUNT" ]]; then
    echo "commit count check failed: expected exactly $EXPECTED_COUNT, got $actual_count" >&2
    exit 1
  fi
else
  if [[ "$actual_count" -lt "$EXPECTED_COUNT" ]]; then
    echo "commit count check failed: expected at least $EXPECTED_COUNT, got $actual_count" >&2
    exit 1
  fi
fi

bad_authors="$(
  git log --format='%an <%ae>' \
    | awk '{ print tolower($0) }' \
    | rg -v "^${EXPECTED_NAME} <${EXPECTED_EMAIL}>$" || true
)"
if [[ -n "$bad_authors" ]]; then
  echo "author check failed: found commits not authored by ${EXPECTED_NAME} <${EXPECTED_EMAIL}>" >&2
  exit 1
fi

if [[ "$STRICT_COMMIT_COUNT" == "1" ]]; then
  echo "commit verification passed: exactly $actual_count commits, author identity matches"
else
  echo "commit verification passed: $actual_count commits (>= $EXPECTED_COUNT), author identity matches"
fi
