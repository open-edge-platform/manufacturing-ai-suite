# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Command Reference — industrial-edge-insights-time-series

Source of truth: `Makefile` in the component root. Re-derive this table from
the live file if it ever disagrees. Helm/Kubernetes deployment is not
supported; there are no Helm targets.

This file only catalogues Make targets. For system requirements,
prerequisites, and step-by-step procedures, use the app's published user
guide at <https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/index.html>
(see "Normative references" in `SKILL.md`).

## App selection

- `app=<name>` selects the sample app (default `wind-turbine-anomaly-detection`).
  Must be one of `SAMPLE_APP_LIST` in the Makefile or `make` errors out.

## Build

| Target | Effect |
|---|---|
| `make build` | `docker compose build --pull`. Builds the data simulator images only (OPC-UA server, MQTT publisher). Builds app images only. It does not build the Time Series Analytics microservice; for that, run `scripts/build-time-series-analytics.sh` first (SKILL.md Step 2a) |
| `make build_copyleft_sources` | Same, plus `--build-arg COPYLEFT_SOURCES=true` |

## Prerequisite / validation targets (auto-invoked by `up_*`)

| Target | Effect |
|---|---|
| `check_env_variables` | Validates `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD` in `.env`. Usernames: letters only, at least 5 characters (`INFLUXDB_USERNAME` must not be `admin`). Passwords: alphanumeric, at least 10 characters, with at least one letter and one digit |

## Deploy (Docker Compose)

| Target | Depends on | Effect |
|---|---|---|
| `make up_mqtt_ingestion` | `check_env_variables down` | Brings up the stack with `TELEGRAF_INPUT_PLUGIN=mqtt_consumer`; starts `num_of_streams` `ia-mqtt-publisher-<i>` instances; then uploads the UDF tar and posts config |
| `make up_opcua_ingestion` | `check_env_variables down` | Same but `TELEGRAF_INPUT_PLUGIN=opcua`, scales `ia-opcua-server` to `num_of_streams` |
| `make down` | — | `docker compose down -v --remove-orphans` (removes volumes) |
| `make status` | — | Lists containers filtered by `ia-`/`mr_`/`model_`/`wind-turbine` name prefixes, waits 20s, then scans last 5 log lines per container for "error" |

After the containers start, both `up_*` targets wait until
`https://${HOST_IP}:${GRAFANA_PORT}/` answers with an nginx `Server` header
and `/ts-api/health` returns `200` or `503`. They then upload
`apps/<app>/time-series-analytics-config/<app>.tar` to `/ts-api/udfs/package`
and post `config.json` (or `config-batch.json`) to `/ts-api/config`.

### Parameters accepted by `up_mqtt_ingestion` / `up_opcua_ingestion`

- `app` — sample app name (default `wind-turbine-anomaly-detection`)
- `num_of_streams` — number of simulated streams (default `1`); >1 triggers
  regeneration of a multi-stream Telegraf config via a local Python venv
  (`generate-telegraf-config.py`). For `up_opcua_ingestion` with >1 stream,
  export `OPCUA_SERVER_PORT_MAPPING=30003-30100` first
  ([Multi-stream ingestion](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/multi-stream-ingestion.html))
- `ingestion_interval` — simulator ingestion interval (default `"1s"`)
- `number_of_data_points_per_stream` — when set, enables
  `ENABLE_BENCHMARKING=true` and sets `BENCHMARK_TOTAL_PTS` (not multiplied
  by `num_of_streams`; see [Benchmarking](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/how-to-guides/benchmarking.html))
- `batch` — append as a second goal (e.g.
  `make up_mqtt_ingestion batch app=wind-turbine-anomaly-detection`) to use
  `config-batch.json` instead of `config.json` for the TSAM config, and swap
  in the `_batch` model variant
- `INCLUDE=validation` — adds `docker-compose-validation.override.yml`
  (system-metrics Grafana dashboard + host-metric Telegraf inputs such as
  `cpu`, `mem`, `disk`, `docker`); `num_of_streams` instance scaling is not
  applied in this mode

## Push / registry

| Target | Effect |
|---|---|
| `make push_images` | `make build` then `docker compose push` (requires `DOCKER_REGISTRY` in `.env` + prior `docker login`) |

## Key env vars (`.env`)

- `HOST_IP` (default `127.0.0.1`) — host used for all Makefile API calls
- `GRAFANA_PORT` (default `3000`)
- `DOCKER_REGISTRY`, `IMAGE_SUFFIX` (push/versioning)
