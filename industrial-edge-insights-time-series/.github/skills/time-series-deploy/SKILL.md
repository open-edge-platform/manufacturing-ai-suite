---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: time-series-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Industrial Edge
  Insights - Time Series sample applications (industrial-edge-insights-time-series,
  e.g. wind-turbine-anomaly-detection) via its Makefile-driven Docker Compose
  path. Use this skill for quick build/deploy/teardown cycles, MQTT vs OPC-UA
  ingestion selection, multi-stream and batch modes, and running the existing
  tests/functional pytest suites. Do not use this skill for application code
  changes, unrelated components, or production rollout decisions.
license: Apache-2.0
compatibility: >-
  Requires a bash-compatible shell, Docker + Docker Compose v2, make, and
  curl. Functional tests additionally require Python 3 and the packages in
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

## Normative references

- `references/command-reference.md` — full Make target catalogue (source of
  truth for every command/flag; re-derive from the live Makefile if it ever
  disagrees with this doc).
- `references/functional-tests.md` — mapping of test files to scenario.

## Step 0: Locate the app root and preflight

1. Resolve the app root: walk up from cwd, or ask git
   (`git rev-parse --show-toplevel`) for the enclosing repo and look for
   `industrial-edge-insights-time-series/Makefile`.
   `cd` into that directory before running any command below — the Makefile
   and the helper scripts read `.env` from the current directory.
2. Confirm `.env` exists and required creds (`INFLUXDB_USERNAME/PASSWORD`,
   `VISUALIZER_GRAFANA_USER/PASSWORD`) are set — ask the user rather than
   inventing values.
3. Confirm `HOST_IP` (default `127.0.0.1`) and `GRAFANA_PORT` (default
   `3000`) in `.env` are correct: `make up_*` uploads the UDF package and
   posts config to `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/...`.
4. Docker preflight: `docker info >/dev/null 2>&1`.

   If the preflight fails, **stop immediately**, report the host blocker, and
   give the exact command sequence the user would need to run once unblocked.

## Step 1: Choose app, ingestion path, and mode

- `app` (default `wind-turbine-anomaly-detection`; this is the only entry in
  `SAMPLE_APP_LIST` today — check the live Makefile before assuming others
  exist).
- Ingestion path: MQTT (`make up_mqtt_ingestion`) or OPC-UA
  (`make up_opcua_ingestion`).
- Optional `num_of_streams=N` (>1 regenerates a multi-stream Telegraf config
  via a Python venv + `generate-telegraf-config.py`), `ingestion_interval`,
  `number_of_data_points_per_stream` (enables benchmarking).
- Optional `batch` goal appended to the ingestion target to use
  `config-batch.json` instead of `config.json` for the Time-Series Analytics
  microservice config.
- Optional `INCLUDE=validation` to add `docker-compose-validation.override.yml`
  (system-metrics dashboard + host-metric Telegraf inputs; CI/validation use).

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
  `wind-turbine` name prefixes and scans recent logs for "error".

## Step 3: Smoke test

From the app root, run
`.github/skills/time-series-deploy/scripts/smoke-check.sh`, which:
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

Or use
`.github/skills/time-series-deploy/scripts/run-functional-tests.sh [default|gpu|security|stability|retention]`
to select the right subset automatically.

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

If Docker is unreachable or required `.env` fields are missing, **do not
stall**: state the blocker plainly, show the exact command sequence the user
would run once unblocked, and stop. Never invent "it worked" output.
