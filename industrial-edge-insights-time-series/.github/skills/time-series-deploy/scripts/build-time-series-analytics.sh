#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Build the Time Series Analytics microservice image from the latest
# edge-ai-libraries source, as in "Build from source" in the user guide:
# https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started/build-from-source.html
# The image is tagged with the name the app's docker-compose.yml expects
# (DOCKER_REGISTRY, TIME_SERIES_ANALYTICS_IMAGE, IMAGE_SUFFIX, WEEKLY_BUILD_DATE
# from the app-root .env), so `make up*` runs it instead of the published image.
#
# Usage: build-time-series-analytics.sh [--copyleft]
#        (run from the app root, or set TIME_SERIES_APP_ROOT)
# Optional environment:
#   EDGE_AI_LIBRARIES_DIR  checkout to clone or update
#                          (default: edge-ai-libraries next to the app's git checkout)
#   EDGE_AI_LIBRARIES_REF  branch or tag to build (default: main)
#
set -euo pipefail

usage() { echo "Usage: $0 [--copyleft]" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

COPYLEFT=false
[ "$#" -le 1 ] || usage
case "${1:-}" in
  "") ;;
  --copyleft) COPYLEFT=true ;;
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
[ -f "$APP_ROOT/.env" ] || fail "$APP_ROOT/.env not found"

read_env() {
  sed -n "s/^$1=//p" "$APP_ROOT/.env" | tail -n 1 | tr -d "\"'"
}

REPO_URL="https://github.com/open-edge-platform/edge-ai-libraries.git"
SERVICE_PATH="microservices/time-series-analytics"
REF="${EDGE_AI_LIBRARIES_REF:-main}"
[[ $REF =~ ^[A-Za-z0-9._/-]+$ && $REF != -* ]] || fail "invalid EDGE_AI_LIBRARIES_REF: $REF"

if [ -n "${EDGE_AI_LIBRARIES_DIR:-}" ]; then
  SRC_DIR="$EDGE_AI_LIBRARIES_DIR"
else
  top="$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$APP_ROOT")"
  SRC_DIR="$(dirname "$top")/edge-ai-libraries"
fi

registry="$(read_env DOCKER_REGISTRY)"
image_name="$(read_env TIME_SERIES_ANALYTICS_IMAGE)"
suffix="$(read_env IMAGE_SUFFIX)"
weekly="$(read_env WEEKLY_BUILD_DATE)"
[ -n "$image_name" ] || fail "TIME_SERIES_ANALYTICS_IMAGE is not set in $APP_ROOT/.env"
for value in "$registry" "$image_name" "$suffix" "$weekly"; do
  [[ $value =~ ^[A-Za-z0-9._/:-]*$ ]] || fail "unexpected image setting in .env: $value"
done
IMAGE="${registry}${image_name}:${suffix:-latest}${weekly:+-${weekly}-weekly}"

echo "== Time Series Analytics source ($SRC_DIR, $REF) =="
if [ -d "$SRC_DIR/.git" ]; then
  origin="$(git -C "$SRC_DIR" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    *edge-ai-libraries*) ;;
    *) fail "$SRC_DIR is not an edge-ai-libraries checkout (origin: ${origin:-none}); set EDGE_AI_LIBRARIES_DIR" ;;
  esac
  [ -z "$(git -C "$SRC_DIR" status --porcelain)" ] \
    || fail "$SRC_DIR has local changes; commit or stash them, or set EDGE_AI_LIBRARIES_DIR"
  git -C "$SRC_DIR" fetch -q "$REPO_URL" "$REF"
  if [ "$(git -C "$SRC_DIR" config --bool core.sparseCheckout || true)" = "true" ]; then
    git -C "$SRC_DIR" sparse-checkout add "$SERVICE_PATH"
  fi
  git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
elif [ -e "$SRC_DIR" ]; then
  fail "$SRC_DIR exists but is not a git checkout; set EDGE_AI_LIBRARIES_DIR"
else
  git clone -q --filter=blob:none --sparse --branch "$REF" "$REPO_URL" "$SRC_DIR"
  git -C "$SRC_DIR" sparse-checkout set "$SERVICE_PATH"
fi
commit="$(git -C "$SRC_DIR" rev-parse --short HEAD)"
DOCKER_DIR="$SRC_DIR/$SERVICE_PATH/docker"
[ -f "$DOCKER_DIR/docker-compose.yml" ] || fail "$DOCKER_DIR/docker-compose.yml not found at $commit"
echo "Source: edge-ai-libraries@$commit"

echo "== Building $IMAGE =="
build_args=()
if $COPYLEFT; then build_args=(--build-arg COPYLEFT_SOURCES=true); fi
# Shell variables override the microservice's own docker/.env, so the tag
# matches the image reference in the app's docker-compose.yml.
(
  cd "$DOCKER_DIR"
  DOCKER_REGISTRY="$registry" TIME_SERIES_ANALYTICS_IMAGE="$image_name" \
    IMAGE_SUFFIX="$suffix" WEEKLY_BUILD_DATE="$weekly" \
    docker compose build ${build_args[@]+"${build_args[@]}"}
)

created="$(docker image inspect --format '{{.Created}}' "$IMAGE" 2>/dev/null)" \
  || fail "build finished but $IMAGE was not found"
echo "OK: built $IMAGE from edge-ai-libraries@$commit (created $created)"
echo "    'make up*' uses this local image; it does not pull the published one."
