#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Smoke-check the Multimodal Weld Defect Detection sample app (Docker Compose).
#
# Usage: smoke-check.sh
#
set -euo pipefail

[ "$#" -eq 0 ] || { echo "Usage: $0" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
cd "$APP_ROOT"

read_env() {
  [ -f .env ] || return 0
  sed -n "s/^$1=//p" .env | tail -n 1 | tr -d "\"'"
}

HOST_IP="$(read_env HOST_IP)"
HOST_IP="${HOST_IP:-127.0.0.1}"
GRAFANA_PORT="$(read_env GRAFANA_PORT)"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
MAX_RETRIES=30
SLEEP_SECS=5

wait_for_url() {
  local url="$1"
  local i=0
  until curl -fsk --connect-timeout 5 --max-time 10 -o /dev/null "$url"; do
    i=$((i + 1))
    if [ "$i" -ge "$MAX_RETRIES" ]; then
      echo "FAIL: could not reach $url after $MAX_RETRIES attempts" >&2
      return 1
    fi
    echo "  not reachable yet ($i/$MAX_RETRIES), retrying in ${SLEEP_SECS}s..."
    sleep "$SLEEP_SECS"
  done
  echo "OK: $url is reachable"
}

echo "== Docker Compose smoke check ($APP_ROOT) =="
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker daemon not reachable" >&2
  exit 1
fi
echo "-- Container status --"
make status || true
echo "-- Endpoint check --"
wait_for_url "https://${HOST_IP}:${GRAFANA_PORT}/"

# Read-only MCP probe (tools/list); runs only for `make up_agentic MCP=true` deployments.
check_mcp() {
  local url="https://${HOST_IP}:${GRAFANA_PORT}/mcp"
  local body code i=0
  body="$(mktemp)"
  while :; do
    code="$(curl -sk -o "$body" -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null || true)"
    if [ "$code" = "200" ] && grep -q '"name":"describe"' "$body"; then
      rm -f "$body"
      echo "OK: $url answered tools/list"
      return 0
    fi
    i=$((i + 1))
    if [ "$i" -ge "$MAX_RETRIES" ]; then
      rm -f "$body"
      echo "FAIL: MCP tools/list at $url returned HTTP $code after $((MAX_RETRIES * SLEEP_SECS))s" >&2
      return 1
    fi
    echo "  MCP not ready (HTTP $code) ($i/$MAX_RETRIES), retrying in ${SLEEP_SECS}s..."
    sleep "$SLEEP_SECS"
  done
}

if [ "$(docker inspect -f '{{.State.Running}}' multimodal-mcp-server 2>/dev/null || true)" = "true" ]; then
  echo "-- MCP endpoint check --"
  check_mcp
fi

echo "Smoke check passed"
