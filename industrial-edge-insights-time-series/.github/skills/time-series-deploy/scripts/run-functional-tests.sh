#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Run the functional pytest suite for industrial-edge-insights-time-series.
# Note: the tests overwrite the credentials in the app's .env file.
#
# Usage: run-functional-tests.sh [default|gpu|security|stability|retention]
#
set -euo pipefail

SUITE="${1:-default}"

usage() {
  echo "Usage: $0 [default|gpu|security|stability|retention]" >&2
  exit 2
}

[ "$#" -le 1 ] || usage

case "$SUITE" in
  default|gpu|security|stability|retention) ;;
  *) usage ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TESTS_DIR="$APP_ROOT/tests/functional"

[ -d "$TESTS_DIR" ] || { echo "FAIL: $TESTS_DIR not found" >&2; exit 1; }
cd "$TESTS_DIR"

if [ ! -d env ]; then
  echo "Creating virtualenv for functional tests..."
  python3 -m venv env
fi
# shellcheck disable=SC1091
source env/bin/activate
pip3 install -q -r ../requirements.txt

case "$SUITE" in
  default)
    pytest -v -s --html=docker_wind_turbine_report.html test_docker_deployment_wind_turbine.py
    ;;
  retention)
    pytest -v -s --html=docker_influxdb_retention_wind_turbine_report.html test_docker_influxdb_retention.py
    ;;
  stability)
    pytest -v -s --html=docker_stability_wind_turbine_report.html test_docker_deployment_stability.py
    ;;
  gpu)
    pytest -v -s -m gpu --html=gpu_docker_report.html test_GPU_docker.py
    ;;
  security)
    pytest -v -s --html=docker_security_report.html test_docker_deployment_security.py
    ;;
esac
