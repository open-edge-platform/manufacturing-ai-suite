# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Command Reference — industrial-edge-insights-multimodal

Source of truth: `Makefile` in the component root. Re-derive this table from
the live file if it ever disagrees. Helm/Kubernetes deployment is not
supported; there are no Helm targets.

This file only catalogues Make targets. For system requirements,
prerequisites (including how to stage the vLLM models), and step-by-step
deployment procedures, use the app's published user guide at
<https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/index.html>
(see "Normative references" in `SKILL.md`).

## The `MCP` flag

`MCP` is a Make variable (default `false`). With `MCP=true`:

- `MCP_COMPOSE_ARG` adds `-f docker-compose-mcp.yml` to `build`,
  `build_copyleft_sources`, `up_agentic`, `down`, and `push_images`.
- `check_env_variables` also validates `MCP_USERNAME` and `MCP_PASSWORD`.
- `up_agentic` uses `NGINX_PROFILE=agentic_mcp` (adds the `/mcp` location)
  instead of `agentic`, and skips `upload_tar_file`.

`up` and `up_vllm` ignore `MCP`. Only the literal value `true` enables it.

## Build

| Target | Effect |
|---|---|
| `make build` | `docker compose -f docker-compose.yml -f docker-compose-vllm.yml -f docker-compose-agentic.yml [-f docker-compose-mcp.yml] build --pull` (MCP overlay only with `MCP=true`). Builds app images only. It does not build the Time Series Analytics microservice; for that, run `scripts/build-time-series-analytics.sh` first (SKILL.md Step 2a) |
| `make build_copyleft_sources` | Same compose file set as `build`, with `--build-arg COPYLEFT_SOURCES=true --pull` |

## Prerequisite / validation targets (auto-invoked by `up*`)

| Target | Effect |
|---|---|
| `check_env_variables` | Validates `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD`, `MTX_WEBRTCICESERVERS2_0_USERNAME/PASSWORD`, `S3_STORAGE_USERNAME/PASSWORD`, `SEAWEEDFS_WEB_AUTH_USER/PASSWORD` in `.env`, plus `MCP_USERNAME/PASSWORD` when `MCP=true`. Usernames: letters only, at least 5 characters (`INFLUXDB_USERNAME` must not be `admin`). Passwords: alphanumeric, at least 10 characters, with at least one letter and one digit |
| `validate_host_ip` | Ensures `HOST_IP` in `.env` is set and is a valid IPv4 address (`localhost` is rejected; use `127.0.0.1` for local-only access) |
| `check_hardware` | Requires Intel Panther Lake (Family 6, Model 204) / Core Ultra 3xx CPU unless `PLATFORM_CHECK=false` (in `.env` or on the `make` command line; CI/validation only) |
| `check_models` | Requires non-empty `configs/vllm/models` and `configs/vllm/huggingface` directories. Populate them with **Download Models** in [Deploy the vLLM service](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-vllm-service.html); `make download_model` does not fill these directories |

## Deploy (Docker Compose)

| Target | Depends on | Effect |
|---|---|---|
| `make up` | `check_env_variables validate_host_ip down` | Default compose file, copies default Grafana dashboard, `docker compose up -d`, then uploads the weld-anomaly UDF tar and posts config to the Time-Series Analytics microservice |
| `make up_vllm` | `check_hardware check_models check_env_variables validate_host_ip down` | Adds `docker-compose-vllm.yml` overlay (`vllm-server`, `multimodal-agentic-ui`), VLM Grafana dashboard, `NGINX_PROFILE=vllm` |
| `make up_agentic` | `check_hardware check_models check_env_variables validate_host_ip down` | Adds agentic + vllm overlays, VLM + agentic Grafana dashboards, `NGINX_PROFILE=agentic`; runs `make download_model` first (can take minutes), brings up all services, then runs `upload_tar_file` |
| `make up_agentic MCP=true` | same, with MCP credential validation | As `up_agentic`, plus `docker-compose-mcp.yml` and `NGINX_PROFILE=agentic_mcp`. Does **not** run `upload_tar_file`; the DL Streamer pipeline uses `config_auto_start_off.json`, so nothing is processed until an MCP client calls `start_pipeline` |
| `make down` | — | `docker compose -f docker-compose.yml -f docker-compose-vllm.yml -f docker-compose-agentic.yml [-f docker-compose-mcp.yml] down -v --remove-orphans` (removes volumes; pass `MCP=true` after an MCP deployment) |
| `make status` | — | Lists containers on the `timeseriessoftware_timeseries_network` network, waits 20s, then scans last 5 log lines per container for "error" |

## Internal helper targets

| Target | Effect |
|---|---|
| `make download_model` | Starts the `model-download` service, polls `http://${HOST_IP}:8200/api/v1/models/results` until ready, requests download/conversion of `LLM_MODEL_NAME` (`LLM_DEVICE`, `LLM_WEIGHT_FORMAT`), then polls the job until completed (up to 600 × 5s) |
| `make wait_for_tsam` | Polls `https://${HOST_IP}:3000/ts-api/health` (port `3000` is hard-coded, not `GRAFANA_PORT`) until the Time-Series Analytics microservice responds |
| `make upload_tar_file` | Builds `configs/time-series-analytics-microservice/weld_anomaly_detector.tar` and uploads it to `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/udfs/package`, then runs `post_config` |
| `make post_config` | Posts `configs/time-series-analytics-microservice/config.json` to `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/config` |

## Push / registry

| Target | Effect |
|---|---|
| `make push_images` | `make build` then `docker compose ... push` (requires `DOCKER_REGISTRY` in `.env` + prior `docker login`; add `MCP=true` to include the MCP server image) |

## MCP server (`docker-compose-mcp.yml`, `mcp-server/`)

- Service `multimodal-mcp-server` (FastMCP, Streamable HTTP, stateless,
  port 8000 inside the Docker network; read-only, non-root container).
- External endpoint: `https://${HOST_IP}:${GRAFANA_PORT}/mcp` via nginx
  (`location = /mcp`, self-signed certificate, no nginx-level auth).
- HTTP Basic auth (`MCP_USERNAME`/`MCP_PASSWORD`) is enforced by the server
  only for `start_pipeline` and `stop_pipeline`.
- The server also exposes `POST /start_pipeline`, `/stop_pipeline` (Basic
  auth) and `/explain` (no auth) on port 8000; nginx does not proxy them.

| Tool | Auth | Effect |
|---|---|---|
| `start_pipeline(vision_inf_device=CPU\|GPU\|NPU, time_series_inf_device=CPU\|GPU)` | Basic | Uploads the UDF package, posts the Time-Series Analytics config, waits up to 120 s for the `weld_anomaly_detector` task, then starts the `weld_defect_classification` DL Streamer pipeline |
| `stop_pipeline()` | Basic | Stops all `QUEUED`/`RUNNING` DL Streamer instances and the time-series task |
| `explain(selected_time)` | — | Explains one fused detection (ISO-8601 timestamp) via `multimodal-agentic-ui` |
| `list_insights_data(page, page_size)` | — | Paginated fusion results |
| `run_agent(time_range=30s\|1m\|5m\|10m\|30m)` | — | Starts an agentic analysis run; returns `run_id` |
| `get_run_results(run_id)` | — | Agent run status/result (`reasoning`, `completed`, `error`) |
| `describe()` | — | Server purpose, tool list, input schemas |

Example client: `mcp-server/example/example_client.py` (see
`mcp-server/example/README.md`).

## Key env vars (`.env`)

- `HOST_IP` (default `127.0.0.1`; must be IPv4)
- `GRAFANA_PORT` (default `3000`)
- `PLATFORM_CHECK` (Makefile default `true`; set `false` to skip hardware gate)
- `LLM_MODEL_NAME`, `LLM_DEVICE`, `LLM_WEIGHT_FORMAT` (agentic model download/selection)
- `MCP_USERNAME`, `MCP_PASSWORD` (empty by default; required with `MCP=true`)
- `MULTIMODAL_MCP_SERVER_IMAGE` (MCP server image name)
- `DOCKER_REGISTRY`, `IMAGE_SUFFIX` (push/versioning)
