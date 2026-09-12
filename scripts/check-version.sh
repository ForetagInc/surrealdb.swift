#!/usr/bin/env bash
#
# Keeps the version constant, the changelog and the native pin from drifting.
# A three-line check beats a release checklist nobody reads.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source scripts/embedded/pin.env

declared="$(sed -n 's/^ *public static let version = "\(.*\)"$/\1/p' Sources/SurrealDB/Runtime/Version.swift)"
changelog="$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' CHANGELOG.md | grep -v '^Unreleased$' | head -1)"
pinned="$(sed -n 's/^ *return "\([0-9a-f]\{40\}\)"$/\1/p' Sources/SurrealDB/Runtime/Version.swift)"

fail=0

if [[ "$declared" != "$changelog" ]]; then
  echo "Version.swift says $declared but the top CHANGELOG entry is $changelog" >&2
  fail=1
fi

if [[ "$pinned" != "$SURREALDB_C_REF" ]]; then
  echo "Version.swift pins native $pinned but scripts/embedded/pin.env says $SURREALDB_C_REF" >&2
  fail=1
fi

if [[ "${GITHUB_REF_NAME:-}" == v* ]]; then
  tag_version="${GITHUB_REF_NAME#v}"
  if [[ "$declared" != "$tag_version" ]]; then
    echo "Tag is $GITHUB_REF_NAME but Version.swift says $declared" >&2
    fail=1
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "version metadata is consistent ($declared, native $pinned)"
fi
exit "$fail"
