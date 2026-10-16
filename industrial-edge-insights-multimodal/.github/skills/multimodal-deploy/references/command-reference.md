# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Command Reference — industrial-edge-insights-multimodal

Source of truth: `Makefile` in the component root. Re-derive this table from
the live file if it ever disagrees. Helm/Kubernetes deployment is not
supported; there are no Helm targets.

## Build

| Target | Effect |
|---|---|
| `make build` | `docker compose -f docker-compose.yml -f docker-compose-vllm.yml -f docker-compose-agentic.yml build --pull` |
| `make build_copyleft_sources` | `docker compose -f docker-compose.yml -f docker-compose-vllm.yml build --build-arg COPYLEFT_SOURCES=true --pull` (agentic overlay not included) |

## Prerequisite / validation targets (auto-invoked by `up*`)

| Target | Effect |
|---|---|
| `check_env_variables` | Validates `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD`, `MTX_WEBRTCICESERVERS2_0_USERNAME/PASSWORD`, `S3_STORAGE_USERNAME/PASSWORD`, `SEAWEEDFS_WEB_AUTH_USER/PASSWORD` in `.env`. Usernames: letters only, at least 5 characters (`INFLUXDB_USERNAME` must not be `admin`). Passwords: alphanumeric, at least 10 characters, with at least one letter and one digit |
| `validate_host_ip` | Ensures `HOST_IP` in `.env` is set and is a valid IPv4 address (`localhost` is rejected; use `127.0.0.1` for local-only access) |
| `check_hardware` | Requires Intel Panther Lake (Family 6, Model 204) / Core Ultra 3xx CPU unless `PLATFORM_CHECK=false` (in `.env` or on the `make` command line; CI/validation only) |
| `check_models` | Requires non-empty `configs/vllm/models` and `configs/vllm/huggingface` directories |

## Deploy (Docker Compose)

| Target | Depends on | Effect |
|---|---|---|
| `make up` | `check_env_variables validate_host_ip down` | Default compose file, copies default Grafana dashboard, `docker compose up -d`, then uploads the weld-anomaly UDF tar and posts config to the Time-Series Analytics microservice |
| `make up_vllm` | `check_hardware check_models check_env_variables validate_host_ip down` | Adds `docker-compose-vllm.yml` overlay (`vllm-server`, `multimodal-agentic-ui`), VLM Grafana dashboard, `NGINX_PROFILE=vllm` |
| `make up_agentic` | `check_hardware check_models check_env_variables validate_host_ip down` | Adds agentic + vllm overlays, VLM + agentic Grafana dashboards, `NGINX_PROFILE=agentic`; runs `make download_model` first (can take minutes), then brings up all services |
| `make down` | — | `docker compose -f docker-compose.yml -f docker-compose-vllm.yml -f docker-compose-agentic.yml down -v --remove-orphans` (removes volumes) |
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
| `make push_images` | `make build` then `docker compose ... push` (requires `DOCKER_REGISTRY` in `.env` + prior `docker login`) |

## Key env vars (`.env`)

- `HOST_IP` (default `127.0.0.1`; must be IPv4)
- `GRAFANA_PORT` (default `3000`)
- `PLATFORM_CHECK` (Makefile default `true`; set `false` to skip hardware gate)
- `LLM_MODEL_NAME`, `LLM_DEVICE`, `LLM_WEIGHT_FORMAT` (agentic model download/selection)
- `DOCKER_REGISTRY`, `IMAGE_SUFFIX` (push/versioning)
