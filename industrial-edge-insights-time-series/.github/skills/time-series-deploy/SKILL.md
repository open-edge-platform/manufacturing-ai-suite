---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: time-series-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Industrial Edge
  Insights - Time Series sample applications (industrial-edge-insights-time-series,
  e.g. wind-turbine-anomaly-detection) via its Makefile-driven Docker Compose
  path. Use this skill for quick build/deploy/teardown cycles, MQTT vs OPC-UA
  ingestion selection, multi-stream, batch, and benchmarking modes, meeting
  prerequisites by following the app's docs/user-guide, and running the
  existing tests/functional pytest suites. Do not use this skill for
  application code changes, unrelated components, or production rollout
  decisions.
license: Apache-2.0
compatibility: >-
  Requires a local checkout of industrial-edge-insights-time-series (its
  Makefile, .env, and docs/user-guide are read at runtime; the skill can be
  installed anywhere, for example with `npx skills add`), a bash-compatible
  shell, Docker + Docker Compose v2, make, and curl. Functional tests additionally require Python 3 and the packages in
  tests/requirements.txt. Helm/Kubernetes deployment is not supported.
metadata:
  author: open-edge-platform
  tags: deployment, docker-compose, manufacturing, time-series, wind-turbine-anomaly-detection
allowed-tools: bash make docker pytest
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
therefore use two bases:

| Base | Paths | How to resolve |
|---|---|---|
| **Skill directory** (`<skill-dir>`, the folder containing this `SKILL.md`) | `references/…`, `scripts/…`, `example-prompts/…` | Always bundled with the skill |
| **App root** (Step 0) | `Makefile`, `.env`, `apps/…`, `configs/…`, `docs/user-guide/…`, `tests/…` | Read from the user's checkout at runtime; never expected inside `<skill-dir>` |

The user guide is intentionally **not** copied into the skill: it ships in
the same checkout as the `Makefile` the skill drives, so it always matches
the version being deployed. Only if `<app-root>/docs/user-guide/` is
missing (for example, an incomplete sparse checkout), fetch the page from
GitHub at the checkout's ref (the commit from `git -C <app-root> rev-parse
HEAD`, or `main` if the app root is not a git checkout):
`https://raw.githubusercontent.com/open-edge-platform/manufacturing-ai-suite/<ref>/industrial-edge-insights-time-series/<path>`.
Say in your report that you used the remote copy.

## Normative references

### User guide (primary source for prerequisites and procedures)

The application's own user guide is the authoritative procedure for system
requirements, prerequisites, and deployment options. **Read the relevant
page and follow its commands as written** instead of composing your own
sequence. Paths are relative to the **app root**, not the skill directory
(see "Path resolution" for the remote fallback):

| Page | Use it for |
|---|---|
| `docs/user-guide/get-started/system-requirements.md` | Hardware/OS/Docker/Python requirements |
| `docs/user-guide/get-started.md` | Docker configuration (non-root, proxy, log rotation), clone commands, `.env` fields, `make up_opcua_ingestion` / `make up_mqtt_ingestion`, UDF inference on GPU, verification (InfluxDB + Grafana), logs |
| `docs/user-guide/get-started/build-from-source.md` | `make build` / `make build_copyleft_sources` (and the optional Time Series Analytics microservice build) |
| `docs/user-guide/how-to-guides/multi-stream-ingestion.md` | `num_of_streams`, including the `OPCUA_SERVER_PORT_MAPPING` export required for OPC-UA multi-stream |
| `docs/user-guide/how-to-guides/benchmarking.md` | `number_of_data_points_per_stream`, stream vs `batch` benchmarking |
| `docs/user-guide/wind-turbine-anomaly-detection/how-to-enable-system-metrics.md` | `INCLUDE=validation` system-metrics dashboard (Telegraf runs as root) |
| `docs/user-guide/wind-turbine-anomaly-detection/index.md` | Data flow and the sample app's `config.json`, UDFs, TICKscripts, models |
| `docs/user-guide/how-to-guides/configure-alerts.md`, `configure-custom-udf.md`, `update-config.md`, `connect-to-secure-mqtt-broker.md`, `connect-to-secure-opcua-server.md`, `write-user-defined-function.md`, `create-a-new-sample-app.md`, `../wind-turbine-anomaly-detection/how-to-select-model.md` | Post-deploy configuration and customization questions |
| `docs/user-guide/troubleshooting.md` | Known runtime issues ("No Data" in Grafana, InfluxDB retention, slow Time Series Analytics start, EMT `docker exec`) |

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
   from `docs/user-guide/get-started.md` (fetch that page remotely, per
   "Path resolution"); its sparse checkout includes `docs/`.
2. Confirm `.env` exists and required creds (`INFLUXDB_USERNAME/PASSWORD`,
   `VISUALIZER_GRAFANA_USER/PASSWORD`) are set — ask the user rather than
   inventing values.
3. Confirm `HOST_IP` (default `127.0.0.1`) and `GRAFANA_PORT` (default
   `3000`) in `.env` are correct: `make up_*` uploads the UDF package and
   posts config to `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/...`.
4. Docker preflight: `docker info >/dev/null 2>&1`.

   If the preflight fails, **stop immediately**, report the host blocker, and
   point the user to the **Configure Docker** section of
   `docs/user-guide/get-started.md` (non-root Docker, proxy) instead of
   waiting or retrying indefinitely.
5. Compare the host against
   `docs/user-guide/get-started/system-requirements.md` (OS, Docker version,
   Python, RAM, storage) and report any shortfall as a warning.

## Step 1: Choose app, ingestion path, and mode

- `app` (default `wind-turbine-anomaly-detection`; this is the only entry in
  `SAMPLE_APP_LIST` today — check the live Makefile before assuming others
  exist).
- Ingestion path: MQTT (`make up_mqtt_ingestion`) or OPC-UA
  (`make up_opcua_ingestion`, supported only for
  `wind-turbine-anomaly-detection`) — see `docs/user-guide/get-started.md`.
- Optional `num_of_streams=N` (>1 regenerates a multi-stream Telegraf config
  via a Python venv + `generate-telegraf-config.py`) and
  `ingestion_interval` — see
  `docs/user-guide/how-to-guides/multi-stream-ingestion.md`.
- Optional `number_of_data_points_per_stream` (enables benchmarking) — see
  `docs/user-guide/how-to-guides/benchmarking.md`.
- Optional `batch` goal appended to the ingestion target to use
  `config-batch.json` instead of `config.json` for the Time-Series Analytics
  microservice config (benchmarking doc).
- Optional `INCLUDE=validation` to add `docker-compose-validation.override.yml`
  (system-metrics dashboard + host-metric Telegraf inputs) — see
  `docs/user-guide/wind-turbine-anomaly-detection/how-to-enable-system-metrics.md`.

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
  `BENCHMARK_TOTAL_PTS` and is **not** multiplied by `num_of_streams`; for
  *N points per stream* pass `N * num_of_streams` (benchmarking doc). For
  `batch`, confirm the app package has batch UDF artifacts.
- **System metrics** (`INCLUDE=validation`): Telegraf runs as `root`; only
  verified for `wind-turbine-anomaly-detection` (system-metrics doc).
- **UDF on GPU**: after deployment, follow **Running User Defined
  Function(UDF) inference on GPU** in `docs/user-guide/get-started.md`
  (replace `localhost` with `${HOST_IP}` and `3000` with `${GRAFANA_PORT}`
  from `.env` when they differ).

Never edit `.env` without the user's permission.

## Step 2: Build and deploy

```bash
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
  `docs/user-guide/troubleshooting.md` before re-running `up_*`.
- For verification, follow **Verify the Output Results** in
  `docs/user-guide/get-started.md` (InfluxDB `datain` measurement +
  Grafana `Wind Turbine Dashboard`).

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
unreachable, no app checkout exists, or required `.env` fields are missing.
In those cases, **do not stall**: state the blocker plainly, cite the
user-guide section that covers it, show the exact command sequence the user
would run once unblocked, and stop. Never invent "it worked" output.
