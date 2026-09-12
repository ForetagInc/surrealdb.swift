#!/usr/bin/env bash
set -euo pipefail

export SURREALDB_RUN_INTEGRATION=1

SURREAL_PID=""
START_MODE=""
INTEGRATION_MODE="${SURREALDB_INTEGRATION_MODE:-auto}"
SURREALDB_BIND_HOST="${SURREALDB_BIND_HOST:-127.0.0.1}"
SURREALDB_PORT="${SURREALDB_PORT:-8000}"

export SURREALDB_HOST="${SURREALDB_HOST:-${SURREALDB_BIND_HOST}:${SURREALDB_PORT}}"
export SURREALDB_USER="${SURREALDB_USER:-root}"
export SURREALDB_PASSWORD="${SURREALDB_PASSWORD:-root}"
export SURREALDB_AUTH_LEVEL="${SURREALDB_AUTH_LEVEL:-root}"
export SURREALDB_NAMESPACE="${SURREALDB_NAMESPACE:-test}"
export SURREALDB_NAME="${SURREALDB_NAME:-test}"

cleanup() {
  if [[ "$START_MODE" == "docker" ]] && command -v docker >/dev/null 2>&1; then
    docker compose -f docker-compose.integration.yml down -v
  fi

  if [[ "$START_MODE" == "local" && -n "$SURREAL_PID" ]]; then
    kill "$SURREAL_PID" >/dev/null 2>&1 || true
  fi
}

wait_for_surreal() {
  local max_attempts=60
  local attempt=1

  until curl -fsS "http://${SURREALDB_BIND_HOST}:${SURREALDB_PORT}/health" >/dev/null 2>&1; do
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "SurrealDB failed to become ready after ${max_attempts} seconds."
      if [[ "$START_MODE" == "local" ]]; then
        echo "--- SurrealDB local log ---"
        cat .build/surrealdb.log || true
      fi
      return 1
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
}

start_docker() {
  docker compose -f docker-compose.integration.yml up -d --wait
  START_MODE="docker"
}

start_local_surreal() {
  local surreal_bin
  surreal_bin="$(command -v surreal || true)"
  local install_dir="${PWD}/.build/surrealdb-bin"

  if [[ -z "$surreal_bin" ]]; then
    surreal_bin="${install_dir}/surreal"
  fi

  if [[ ! -x "$surreal_bin" ]]; then
    echo "Docker unavailable; installing SurrealDB binary via install script..."
    mkdir -p "$install_dir"
    curl -sSf https://install.surrealdb.com | sh -s -- "$install_dir"
    surreal_bin="${install_dir}/surreal"
  fi

  if [[ ! -x "$surreal_bin" ]]; then
    echo "Unable to find executable 'surreal' binary."
    return 1
  fi

  mkdir -p .build
  "${surreal_bin}" start --log info --user "${SURREALDB_USER}" --pass "${SURREALDB_PASSWORD}" memory --bind "${SURREALDB_BIND_HOST}:${SURREALDB_PORT}" > .build/surrealdb.log 2>&1 &
  SURREAL_PID="$!"
  START_MODE="local"
}

trap cleanup EXIT

if [[ "$INTEGRATION_MODE" == "docker" ]]; then
  start_docker
elif [[ "$INTEGRATION_MODE" == "local" ]]; then
  start_local_surreal
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if ! start_docker; then
    echo "Docker is available but compose startup failed; falling back to local SurrealDB binary."
    start_local_surreal
  fi
else
  start_local_surreal
fi

wait_for_surreal

# Run separately: live queries and session forking share server state and
# interfere when executed in one process.
INTEGRATION_TESTS=(
  integration_wsAuthQueryCrud
  integration_httpParity
  integration_wsFullCRUDQueries
  integration_wsFunctionAndGeoQueries
  integration_wsLiveQueries
  integration_sessionForkIsolationAndClose
)

# Fail loudly if a test exists but nobody added it above. integration_sessionFork-
# IsolationAndClose sat unlisted and therefore unrun; this stops that recurring.
discovered="$(grep -rho 'func integration_[A-Za-z0-9_]*' Tests/SurrealDBTests \
  | sed 's/func //' \
  | grep -v '^integration_embedded' \
  | sort -u)"
listed="$(printf '%s\n' "${INTEGRATION_TESTS[@]}" | sort -u)"
missing="$(comm -23 <(echo "$discovered") <(echo "$listed"))"

if [[ -n "$missing" ]]; then
  echo "Integration tests missing from scripts/test-integration.sh:" >&2
  echo "$missing" >&2
  exit 1
fi

for test_name in "${INTEGRATION_TESTS[@]}"; do
  swift test --filter "$test_name"
done
