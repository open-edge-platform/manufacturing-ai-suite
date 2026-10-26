#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Run the functional pytest suite for industrial-edge-insights-time-series.
# Note: the tests overwrite the credentials in the app's .env file.
#
# Usage: run-functional-tests.sh [default|gpu|security|stability|retention]
#        (run from the app root, or set TIME_SERIES_APP_ROOT)
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

# The skill may be installed outside the repo (for example via `npx skills add`),
# so resolve the app root from TIME_SERIES_APP_ROOT, then the current directory,
# then the in-repo location (.github/skills/time-series-deploy/scripts).
is_app_root() {
  [ -f "$1/Makefile" ] && [ -f "$1/generate-telegraf-config.py" ] && [ -d "$1/apps" ]
}
APP_ROOT=""
for candidate in "${TIME_SERIES_APP_ROOT:-}" "$PWD" "$SCRIPT_DIR/../../../.."; do
  if [ -n "$candidate" ] && is_app_root "$candidate"; then
    APP_ROOT="$(cd "$candidate" && pwd)"
    break
  fi
done
if [ -z "$APP_ROOT" ]; then
  echo "FAIL: industrial-edge-insights-time-series app root not found." >&2
  echo "      Run from the app root or set TIME_SERIES_APP_ROOT=/path/to/industrial-edge-insights-time-series" >&2
  echo "      To get a checkout, see 'Clone source code' in https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html" >&2
  exit 1
fi
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
