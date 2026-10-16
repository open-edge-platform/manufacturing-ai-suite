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

echo "Smoke check passed"
