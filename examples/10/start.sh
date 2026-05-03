#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

port_is_available() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .
  else
    ! nc -z 127.0.0.1 "${port}" >/dev/null 2>&1
  fi
}

pick_available_port() {
  local port="$1"
  while ! port_is_available "${port}"; do
    port=$((port + 1))
  done
  echo "${port}"
}

cidr_prefix() {
  echo "$1" | cut -d/ -f2
}

default_parent_interface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

container_ip() {
  local container="$1"
  local network="$2"
  docker inspect -f "{{with index .NetworkSettings.Networks \"${network}\"}}{{.IPAddress}}{{end}}" "${container}"
}

print_summary_table() {
  local project="$1"
  local network_name="$2"
  local master_ip="$3"
  local floating_ip="$4"
  local cgi_ip="$5"
  local cgi_port="$6"
  local cgi_url_local="$7"
  local cgi_url_host="$8"

  printf "\n%-22s | %s\n" "Field" "Value"
  printf "%-22s-+-%s\n" "----------------------" "-----------------------------------------------"
  printf "%-22s | %s\n" "Project" "${project}"
  printf "%-22s | %s\n" "Cluster network" "${network_name}"
  printf "%-22s | %s\n" "Master internal IP" "${master_ip}"
  printf "%-22s | %s\n" "Master floating IP" "${floating_ip}"
  printf "%-22s | %s\n" "CGI internal IP" "${cgi_ip}"
  printf "%-22s | %s\n" "CGI external port" "${cgi_port}"
  printf "%-22s | %s\n" "CGI URL (Local)" "${cgi_url_local}"
  printf "%-22s | %s\n" "CGI URL (Host)" "${cgi_url_host}"
}

export REGISTRY="${REGISTRY:-saywish-mini-al:443}"
export PROJECT="${PROJECT:-leilfs}"
export SAUNAFS_VERSION="${SAUNAFS_VERSION:-5.9.0-1}"
export DISTRO="${DISTRO:-24.04}"
export BRANCH="${BRANCH:-$(git branch --show-current 2>/dev/null || echo "main")}"
export LEILFS_TAG="${LEILFS_TAG:-ubuntu-${DISTRO}-leilfs-${SAUNAFS_VERSION}-${BRANCH}}"
export LEILFS_SUBNET="${LEILFS_SUBNET:-172.32.0.0/24}"
export FLOATING_IP="${FLOATING_IP:-172.32.0.250}"
export MASTER1_IP="${MASTER1_IP:-172.32.0.251}"
export MASTER_HOST="${MASTER_HOST:-sfsmaster}"
export SAUNAFS_HDD_COUNT="${SAUNAFS_HDD_COUNT:-10}"
export CGI_EXTERNAL_PORT_BASE="${CGI_EXTERNAL_PORT_BASE:-29435}"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-leilfs-10}"
METALOGGER_SCALE="${METALOGGER_SCALE:-10}"
CGI_SCALE="${CGI_SCALE:-1}"
CHUNKSERVER_SCALE="${CHUNKSERVER_SCALE:-10}"
CLIENT_SCALE="${CLIENT_SCALE:-10}"
VIP_PREFIX="${FLOATING_IP_CIDR_PREFIX:-$(cidr_prefix "${LEILFS_SUBNET}")}"
MASTER_CONTAINER="${PROJECT_NAME}-master-1"
CGI_CONTAINER="${PROJECT_NAME}-cgi-1"
CLUSTER_NETWORK_NAME="${PROJECT_NAME}_leilfsnet"

export CGI_EXTERNAL_PORT="$(pick_available_port "${CGI_EXTERNAL_PORT_BASE}")"

docker compose \
  -p "${PROJECT_NAME}" \
  -f "${COMPOSE_FILE}" \
  up -d --remove-orphans master

# Wait for master to be ready and network to be attached
sleep 2

docker exec "${MASTER_CONTAINER}" sh -lc "ip addr show dev eth0 | grep -q ' ${FLOATING_IP}/${VIP_PREFIX} ' || ip addr add ${FLOATING_IP}/${VIP_PREFIX} dev eth0"

docker compose \
  -p "${PROJECT_NAME}" \
  -f "${COMPOSE_FILE}" \
  up -d \
  --remove-orphans \
  --scale metalogger="${METALOGGER_SCALE}" \
  --scale cgi="${CGI_SCALE}" \
  --scale chunkserver="${CHUNKSERVER_SCALE}" \
  --scale client="${CLIENT_SCALE}" \
  metalogger cgi cgi-publish chunkserver client

MASTER_INTERNAL_IP="$(container_ip "${MASTER_CONTAINER}" "${CLUSTER_NETWORK_NAME}")"
CGI_INTERNAL_IP="$(container_ip "${CGI_CONTAINER}" "${CLUSTER_NETWORK_NAME}")"

print_summary_table \
  "${PROJECT_NAME}" \
  "${CLUSTER_NETWORK_NAME}" \
  "${MASTER_INTERNAL_IP}" \
  "${FLOATING_IP}" \
  "${CGI_INTERNAL_IP}" \
  "${CGI_EXTERNAL_PORT}" \
  "http://127.0.0.1:${CGI_EXTERNAL_PORT}/sfs.cgi?masterhost=sfsmaster&masterport=9421" \
  "http://${HOSTNAME}:${CGI_EXTERNAL_PORT}/sfs.cgi?masterhost=sfsmaster&masterport=9421"
