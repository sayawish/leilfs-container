#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-leilfs-10}"
CLUSTER_NETWORK_NAME="${CLUSTER_NETWORK_NAME:-leilfs-10-net}"

docker compose \
  -p "${PROJECT_NAME}" \
  -f "${COMPOSE_FILE}" \
  down \
  --remove-orphans

docker network rm "${CLUSTER_NETWORK_NAME}" >/dev/null 2>&1 || true
