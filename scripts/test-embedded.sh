#!/usr/bin/env bash
#
# Runs the embedded (mem://) test suite. Unlike test-integration.sh this needs no
# server at all (the database runs in-process), but it does need the native
# library, so it builds one if it is not already there.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/.build/embedded/out"
HOST_TRIPLE="$(rustc -vV | awk '/^host:/{print $2}')"

if [[ ! -f "$OUT/slices/$HOST_TRIPLE/libsurrealdb_c.a" ]]; then
  ./scripts/build-embedded.sh
fi

export PKG_CONFIG_PATH="$OUT/pkgconfig:${PKG_CONFIG_PATH:-}"
export SURREALDB_EMBEDDED=1

# SwiftPM's manifest cache key does not include the environment, so a cached
# manifest from a non-embedded build would silently drop the C target.
swift test --manifest-cache none --filter integration_embedded
