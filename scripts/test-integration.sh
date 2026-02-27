#!/usr/bin/env bash
set -euo pipefail

export SURREALDB_RUN_INTEGRATION=1
export SURREALDB_SKIP_SIGNIN=0

SURREAL_PID=""
START_MODE=""
INTEGRATION_MODE="${SURREALDB_INTEGRATION_MODE:-auto}"
SURREALDB_HOST="${SURREALDB_HOST:-127.0.0.1}"
SURREALDB_PORT="${SURREALDB_PORT:-8000}"

export SURREALDB_WS_ENDPOINT="ws://${SURREALDB_HOST}:${SURREALDB_PORT}"
export SURREALDB_HTTP_ENDPOINT="http://${SURREALDB_HOST}:${SURREALDB_PORT}"
export SURREALDB_ROOT_USER="${SURREALDB_ROOT_USER:-root}"
export SURREALDB_ROOT_PASS="${SURREALDB_ROOT_PASS:-root}"

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

  until curl -fsS "${SURREALDB_HTTP_ENDPOINT}/health" >/dev/null 2>&1; do
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
  export SURREALDB_SKIP_SIGNIN=1
  "${surreal_bin}" start --log info --unauthenticated memory --bind "${SURREALDB_HOST}:${SURREALDB_PORT}" > .build/surrealdb.log 2>&1 &
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

swift test --filter integration_wsAuthQueryCrud
swift test --filter integration_httpParity
swift test --filter integration_wsFullCRUDQueries
swift test --filter integration_wsFunctionAndGeoQueries
