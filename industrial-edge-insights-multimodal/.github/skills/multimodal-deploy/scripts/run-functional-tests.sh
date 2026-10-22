#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Run the functional pytest suite for industrial-edge-insights-multimodal.
# Note: the tests overwrite credentials and HOST_IP in the app's .env file.
#
# Usage: run-functional-tests.sh [cpu|gpu|npu]   (run from the app root, or set MULTIMODAL_APP_ROOT)
#
set -euo pipefail

HW="${1:-cpu}"

usage() {
  echo "Usage: $0 [cpu|gpu|npu]" >&2
  exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The skill may be installed outside the repo (for example via `npx skills add`),
# so resolve the app root from MULTIMODAL_APP_ROOT, then the current directory,
# then the in-repo location (.github/skills/multimodal-deploy/scripts).
is_app_root() {
  [ -f "$1/Makefile" ] && [ -f "$1/docker-compose-agentic.yml" ] && [ -d "$1/fusion-analytics" ]
}
APP_ROOT=""
for candidate in "${MULTIMODAL_APP_ROOT:-}" "$PWD" "$SCRIPT_DIR/../../../.."; do
  if [ -n "$candidate" ] && is_app_root "$candidate"; then
    APP_ROOT="$(cd "$candidate" && pwd)"
    break
  fi
done
if [ -z "$APP_ROOT" ]; then
  echo "FAIL: industrial-edge-insights-multimodal app root not found." >&2
  echo "      Run from the app root or set MULTIMODAL_APP_ROOT=/path/to/industrial-edge-insights-multimodal" >&2
  echo "      To get a checkout, see 'Clone source code' in https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started.html" >&2
  exit 1
fi
TESTS_DIR="$APP_ROOT/tests/functional"

[ -d "$TESTS_DIR" ] || { echo "FAIL: $TESTS_DIR not found" >&2; exit 1; }
cd "$TESTS_DIR"

case "$HW" in
  cpu|gpu|npu) ;;
  *) usage ;;
esac

if [ ! -d env ]; then
  echo "Creating virtualenv for functional tests..."
  python3 -m venv env
fi
# shellcheck disable=SC1091
source env/bin/activate
pip3 install -q -r ../requirements.txt

case "$HW" in
  cpu)
    pytest -v -s --html=docker_multimodal_report.html test_docker_deployment_multimodal.py
    ;;
  gpu)
    pytest -v -s -m gpu --html=gpu_docker_multimodal_report.html test_GPU_docker_multimodal.py
    ;;
  npu)
    pytest -v -s --html=npu_docker_multimodal_report.html test_NPU_docker_multimodal.py
    ;;
esac
