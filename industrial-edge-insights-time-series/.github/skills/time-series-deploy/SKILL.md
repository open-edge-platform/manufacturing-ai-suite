---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: time-series-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Industrial Edge
  Insights - Time Series sample applications (industrial-edge-insights-time-series,
  e.g. wind-turbine-anomaly-detection) via its Makefile-driven Docker Compose
  path. Use this skill for quick build/deploy/teardown cycles, building the
  Time Series Analytics microservice from the latest source as in the user
  guide's Build from source page (only when the request explicitly asks for
  it), MQTT vs OPC-UA
  ingestion selection, multi-stream, batch, and benchmarking modes, meeting
  prerequisites by following the app's published user guide, and running the
  existing tests/functional pytest suites. Do not use this skill for
  application code changes, unrelated components, or production rollout
  decisions.
license: Apache-2.0
compatibility: >-
  Requires a local checkout of industrial-edge-insights-time-series (its
  Makefile, .env, apps, configs, and tests are read at runtime; the skill
  itself can be installed anywhere), web access to the published user guide
  (or the checkout's docs/user-guide copy), bash, Docker + Docker Compose v2,
  make, curl, and git. Functional tests need Python 3 and
  tests/requirements.txt. Helm/Kubernetes is not supported.
metadata:
  author: open-edge-platform
  tags: deployment, docker-compose, manufacturing, time-series, wind-turbine-anomaly-detection
allowed-tools: bash, make, docker, pytest
---

# Industrial Edge Insights - Time Series — Deploy Skill

Drive **industrial-edge-insights-time-series** builds, deployments, smoke
checks, and functional tests through its real `Makefile`, `docker-compose.yml`,
and `tests/functional/` pytest suite. Ground every answer in those files — do
not invent Make targets, flags, ports, or env vars. **Run the commands
yourself and relay actual output**; never fabricate results.

Scope: this skill only applies to
`industrial-edge-insights-time-series`. The companion
component `industrial-edge-insights-multimodal` has its own
`multimodal-deploy` skill — do not mix the two. Helm/Kubernetes deployment
has been removed from this app; if asked for it, say so and offer the Docker
Compose path instead.

## Path resolution (the skill may be installed outside the repo)

This skill may live inside the repo
(`industrial-edge-insights-time-series/.github/skills/time-series-deploy/`) or
be installed standalone into an agent's skills directory (for example with
`npx skills add`, which copies only this skill folder). Paths in this skill
therefore use three bases:

| Base | Paths | How to resolve |
|---|---|---|
| **Skill directory** (`<skill-dir>`, the folder containing this `SKILL.md`) | `references/…`, `scripts/…`, `example-prompts/…` | Always bundled with the skill |
| **App root** (Step 0) | `Makefile`, `.env`, `apps/…`, `configs/…`, `tests/…` | Read from the user's checkout at runtime; never expected inside `<skill-dir>` |
| **User guide** | Pages linked under "Normative references" | Published at <https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/index.html>; page `<page>.html` there is also in the checkout as `docs/user-guide/<page>.md` |

The user guide is intentionally **not** copied into the skill. Open each page
by its published URL, so the skill works without the repository's `docs/`
folder: from a standalone install, a sparse checkout, or an agent whose
terminal runs on another host (for example, over SSH). Two exceptions:

- The published guide (`/dev/`) tracks the development branch. If the app
  root is on a release tag or branch (`git -C <app-root> describe --tags
  --exact-match` or `git -C <app-root> branch --show-current`) and
  `<app-root>/docs/user-guide/<page>.md` exists, read that copy instead,
  because it matches the `Makefile` you are driving.
- If the published site is unreachable (offline host, proxy), read the
  checkout copy.

Name the source you used (URL or checkout path) in your report.

## Normative references

### User guide (primary source for prerequisites and procedures)

The application's own user guide is the authoritative procedure for system
requirements, prerequisites, and deployment options. **Read the relevant
page and follow its commands as written** instead of composing your own
sequence (see "Path resolution" for when to read the checkout copy instead):

| Page | Use it for |
|---|---|
| [System requirements](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started/system-requirements.html) | Hardware/OS/Docker/Python requirements |
| [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html) | Docker configuration (non-root, proxy, log rotation), clone commands, `.env` fields, `make up_opcua_ingestion` / `make up_mqtt_ingestion`, UDF inference on GPU, verification (InfluxDB + Grafana), logs |
| [Build from source](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started/build-from-source.html) | `make build` / `make build_copyleft_sources`, and, only when explicitly requested, building the Time Series Analytics microservice from the latest `edge-ai-libraries` source first (Step 2a) |
| [Multi-stream ingestion](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/multi-stream-ingestion.html) | `num_of_streams`, including the `OPCUA_SERVER_PORT_MAPPING` export required for OPC-UA multi-stream |
| [Benchmarking](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/benchmarking.html) | `number_of_data_points_per_stream`, stream vs `batch` benchmarking |
| [Enable system metrics](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/wind-turbine-anomaly-detection/how-to-enable-system-metrics.html) | `INCLUDE=validation` system-metrics dashboard (Telegraf runs as root) |
| [Wind turbine anomaly detection](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/wind-turbine-anomaly-detection/index.html) | Data flow and the sample app's `config.json`, UDFs, TICKscripts, models |
| [Configure alerts](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/configure-alerts.html), [Configure a custom UDF](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/configure-custom-udf.html), [Update config](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/update-config.html), [Connect to a secure MQTT broker](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/connect-to-secure-mqtt-broker.html), [Connect to a secure OPC-UA server](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/connect-to-secure-opcua-server.html), [Write a user-defined function](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/write-user-defined-function.html), [Create a new sample app](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/create-a-new-sample-app.html), [Select a model](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/wind-turbine-anomaly-detection/how-to-select-model.html) | Post-deploy configuration and customization questions |
| [Troubleshooting](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/troubleshooting.html) | Known runtime issues ("No Data" in Grafana, InfluxDB retention, slow Time Series Analytics start, EMT `docker exec`) |

### Skill-local references (Makefile/test facts not covered by the user guide)

Relative to `<skill-dir>`:

- `references/command-reference.md` — Make target catalogue and parameters.
  The live `Makefile` is the source of truth for target behaviour; if the
  user guide and the `Makefile` disagree, follow the `Makefile` and mention
  the discrepancy in your report.
- `references/functional-tests.md` — mapping of test files to scenario.

## Step 0: Locate the app root and preflight

1. Resolve the app root (a directory containing `Makefile`,
   `generate-telegraf-config.py`, and `apps/`), in this order: a path the
   user gave; `$TIME_SERIES_APP_ROOT`; cwd or one of its parents;
   `<git toplevel>/industrial-edge-insights-time-series` from
   `git rev-parse --show-toplevel`. Do not derive it from `<skill-dir>`.
   `cd` into that directory before running any command below — the Makefile
   and the helper scripts read `.env` from the current directory.
   If no checkout exists, stop and offer the **Clone source code** commands
   from [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html).
2. Confirm `.env` exists and required creds (`INFLUXDB_USERNAME/PASSWORD`,
   `VISUALIZER_GRAFANA_USER/PASSWORD`) are set — ask the user rather than
   inventing values.
3. Confirm `HOST_IP` (default `127.0.0.1`) and `GRAFANA_PORT` (default
   `3000`) in `.env` are correct: `make up_*` uploads the UDF package and
   posts config to `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/...`.
4. Docker preflight: `docker info >/dev/null 2>&1`.

   If the preflight fails, **stop immediately**, report the host blocker, and
   point the user to the **Configure Docker** section of
   [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html) (non-root Docker, proxy) instead of
   waiting or retrying indefinitely.
5. Compare the host against
   [System requirements](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started/system-requirements.html) (OS, Docker version,
   Python, RAM, storage) and report any shortfall as a warning.

## Step 1: Choose app, ingestion path, and mode

- `app` (default `wind-turbine-anomaly-detection`; this is the only entry in
  `SAMPLE_APP_LIST` today — check the live Makefile before assuming others
  exist).
- Ingestion path: MQTT (`make up_mqtt_ingestion`) or OPC-UA
  (`make up_opcua_ingestion`, supported only for
  `wind-turbine-anomaly-detection`) — see [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html).
- Optional `num_of_streams=N` (>1 regenerates a multi-stream Telegraf config
  via a Python venv + `generate-telegraf-config.py`) and
  `ingestion_interval` — see
  [Multi-stream ingestion](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/multi-stream-ingestion.html).
- Optional `number_of_data_points_per_stream` (enables benchmarking) — see
  [Benchmarking](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/benchmarking.html).
- Optional `batch` goal appended to the ingestion target to use
  `config-batch.json` instead of `config.json` for the Time-Series Analytics
  microservice config (benchmarking doc).
- Optional `INCLUDE=validation` to add `docker-compose-validation.override.yml`
  (system-metrics dashboard + host-metric Telegraf inputs) — see
  [Enable system metrics](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/wind-turbine-anomaly-detection/how-to-enable-system-metrics.html).

## Step 1b: Meet option prerequisites (from the user guide)

Read the doc for each option chosen above and satisfy its prerequisites
before running an `up_*` target. When the user asks you to "meet
prerequisites", this is part of the job — apply documented fixes instead of
stopping at the first failing check. Known doc-only prerequisites:

- **OPC-UA multi-stream** (`make up_opcua_ingestion num_of_streams=N`, N>1):
  `export OPCUA_SERVER_PORT_MAPPING=30003-30100` in the same shell before
  `make` (multi-stream doc). Without it, `docker-compose.yml` maps a single
  host port (`30003`) and the scaled OPC-UA servers collide.
- **Benchmarking**: `number_of_data_points_per_stream` is forwarded as
  `BENCHMARK_TOTAL_PTS`, which the wind-turbine UDFs apply **per stream**
  (counted per `source`). For *N points per stream* pass `N` unchanged; the
  total processed is `N * num_of_streams`. The benchmarking doc's advice to
  pass `N * num_of_streams` conflicts with the UDF code — follow the code and
  mention the discrepancy in your report. For `batch`, confirm the app
  package has batch UDF artifacts.
- **System metrics** (`INCLUDE=validation`): Telegraf runs as `root`; only
  verified for `wind-turbine-anomaly-detection` (system-metrics doc).
- **UDF on GPU**: after deployment, follow **Running User Defined
  Function(UDF) inference on GPU** in [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html)
  (replace `localhost` with `${HOST_IP}` and `3000` with `${GRAFANA_PORT}`
  from `.env` when they differ).

Never edit `.env` without the user's permission.

## Step 2: Build and deploy

```bash
<skill-dir>/scripts/build-time-series-analytics.sh   # ONLY if explicitly asked to build Time Series Analytics (Step 2a)
make build                                   # or: make build_copyleft_sources
make up_mqtt_ingestion app=wind-turbine-anomaly-detection
# or
make up_opcua_ingestion app=wind-turbine-anomaly-detection
# optional batch mode:
make up_mqtt_ingestion batch app=wind-turbine-anomaly-detection
make status
```

- Both `up_*` targets call `check_env_variables` and `down` first.
- `make status` lists containers filtered by `ia-`, `mr_`, `model_`,
  `wind-turbine` name prefixes and scans recent logs for "error". Report it
  verbatim. Per the user guide, Grafana `user token not found` errors before
  the first login are benign.
- Grafana may show "No Data" at first while the Time Series Analytics
  microservice installs its Python packages — check
  [Troubleshooting](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/troubleshooting.html) before re-running `up_*`.
- For verification, follow **Verify the Output Results** in
  [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started.html) (InfluxDB `datain` measurement +
  Grafana `Wind Turbine Dashboard`).

## Step 2a: Build the Time Series Analytics microservice from source (explicit request only)

This step is **conditional**. Run it only when the user's request explicitly
asks to build the Time Series Analytics microservice, for example "build the
Time Series Analytics microservice", "build Time Series Analytics from
source", or "build with the latest Time Series Analytics microservice".

Do **not** run it for any other build or deploy request: "build", "build
and deploy", "build from source", `make build`, or
`make build_copyleft_sources`. For those, run only `make build` (Step 2),
which builds the app images and keeps the published Time Series Analytics
image, because that compose service has no `build:` section. Do not infer the
request from symptoms; report the symptom and let the user ask for the build.

When the request does ask for it, follow steps 1 and 2 of
[Build from source](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/get-started/build-from-source.html),
from the app root (or with `TIME_SERIES_APP_ROOT` set):

```bash
<skill-dir>/scripts/build-time-series-analytics.sh             # step 1; add --copyleft when the request also asks for make build_copyleft_sources
make build                                                     # step 2 (see Step 2 for variants and flags)
```

The script runs the guide's step 1 with these additions:

- **Latest source.** It clones `edge-ai-libraries` at `main` (as in the
  guide; override with `EDGE_AI_LIBRARIES_REF`) into
  `EDGE_AI_LIBRARIES_DIR`, by default `edge-ai-libraries` next to the app's
  git checkout, which is the layout the guide's clone commands produce. The
  clone is blobless and sparse (only `microservices/time-series-analytics`,
  the build context). An existing checkout is fetched and detached at the
  latest commit; it must have no local changes, and no local branch is
  moved.
- **Matching tag.** It runs `docker compose build` (with
  `--build-arg COPYLEFT_SOURCES=true` for `--copyleft`) in
  `microservices/time-series-analytics/docker`, overriding
  `DOCKER_REGISTRY`, `TIME_SERIES_ANALYTICS_IMAGE`, `IMAGE_SUFFIX`, and
  `WEEKLY_BUILD_DATE` with the values in the app's `.env`. Without this, the
  microservice's own `docker/.env` decides the tag, and if it differs the app
  keeps running the published image.
- **Verification.** It confirms the image exists and prints the tag and the
  `edge-ai-libraries` commit. Report both to the user.

`make up*` runs `docker compose up -d` without pulling, so the deployment
uses the local image. The local build replaces the published tag on this
host; `docker pull <image>` restores the published one. The build downloads
base images and packages, so it can take a while; a failed clone, fetch, or
build (network, proxy, disk) is a real blocker. Report the failing output and
stop.
A `curl` exit code 60 inside the build means a TLS-inspecting proxy whose CA
the build does not trust. Do not disable certificate checks; tell the user
the proxy CA must be trusted for the build, and stop.

## Step 3: Smoke test

From the app root, run `<skill-dir>/scripts/smoke-check.sh` (or set
`TIME_SERIES_APP_ROOT` when running it from elsewhere), which:
- verifies the Docker daemon is reachable,
- runs `make status`,
- curls the nginx/Grafana endpoint `https://${HOST_IP}:${GRAFANA_PORT}/`
  (values read from `.env`; `-k` for the self-signed cert) with retries.

Report the script's pass/fail output directly to the user.

## Step 4: Functional tests

See `references/functional-tests.md` for the full file-to-scenario mapping.
Typical invocation (from `tests/functional/`, after
`pip install -r ../requirements.txt`):

```bash
pytest -v -s --html=docker_wind_turbine_report.html test_docker_deployment_wind_turbine.py
pytest -v -s --html=docker_influxdb_retention_wind_turbine_report.html test_docker_influxdb_retention.py
pytest -v -s --html=docker_stability_wind_turbine_report.html test_docker_deployment_stability.py
pytest -v -s -m gpu --html=gpu_docker_report.html test_GPU_docker.py
pytest -v -s --html=docker_security_report.html test_docker_deployment_security.py
```

Or run
`<skill-dir>/scripts/run-functional-tests.sh [default|gpu|security|stability|retention]`
from the app root to select the right subset automatically.

The tests deploy and tear down the stack themselves, and they **overwrite the
credentials in `.env`** with generated test values. Tell the user before
running them, and suggest backing up `.env` first (for example,
`cp .env .env.bak`). Summarize pytest's pass/fail counts in your answer; do
not just point at the report file.

## Step 5: Cleanup

```bash
make down          # removes volumes
```

## Answer contract when blocked

A failing prerequisite that the user guide documents how to fix (for
example, the OPC-UA multi-stream port mapping) is **not** a blocker: apply
the documented procedure (Step 1b), then continue.

Real blockers are conditions you cannot or must not fix yourself: Docker is
unreachable, no app checkout exists, required `.env` fields are missing, or
the Time Series Analytics source build (when requested) fails.
In those cases, **do not stall**: state the blocker plainly, cite the
user-guide section that covers it, show the exact command sequence the user
would run once unblocked, and stop. Never invent "it worked" output.
