#!/usr/bin/env bash
set -euo pipefail

export SURREALDB_RUN_INTEGRATION=1

docker compose -f docker-compose.integration.yml up -d --wait
trap 'docker compose -f docker-compose.integration.yml down -v' EXIT

swift test --filter integration_
