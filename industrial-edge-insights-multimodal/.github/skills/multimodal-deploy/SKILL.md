---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: multimodal-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Multimodal Weld
  Defect Detection sample application (industrial-edge-insights-multimodal)
  via its Makefile-driven Docker Compose path. Use this skill for quick
  build/deploy/teardown cycles, variant selection (default, vLLM, agentic,
  agentic with the MCP server via `make up_agentic MCP=true`),
  hardware/model prerequisite checks, MCP endpoint checks, and running the
  existing tests/functional pytest suites. Do not use this skill for
  application code changes, unrelated components, or production rollout
  decisions.
license: Apache-2.0
compatibility: >-
  Requires a bash-compatible shell, Docker + Docker Compose v2, make, and
  curl. Functional tests additionally require Python 3 and the packages in
  tests/requirements.txt; the MCP example client requires Python 3 and
  mcp-server/example/requirements.txt. Helm/Kubernetes deployment is not
  supported.
metadata:
  author: open-edge-platform
  tags: deployment, docker-compose, manufacturing, multimodal, weld-defect-detection
allowed-tools: bash make docker pytest
---

# Multimodal Weld Defect Detection — Deploy Skill

Drive **industrial-edge-insights-multimodal** builds, deployments, smoke
checks, and functional tests through its real `Makefile`, `docker-compose*.yml`
files, and `tests/functional/` pytest suite. Ground every answer in those
files — do not invent Make targets, flags, ports, or env vars. **Run the
commands yourself and relay actual output**; never fabricate results.

Scope: this skill only applies to
`industrial-edge-insights-multimodal`. The companion
component `industrial-edge-insights-time-series` has its own
`time-series-deploy` skill — do not mix the two. Helm/Kubernetes deployment
has been removed from this app; if asked for it, say so and offer the Docker
Compose path instead.

## Normative references

- `references/command-reference.md` — full Make target catalogue (source of
  truth for every command/flag used below; re-derive from the live Makefile
  if it ever disagrees with this doc).
- `references/functional-tests.md` — mapping of test files to hardware.

## Step 0: Locate the app root and preflight

1. Resolve the app root: walk up from cwd, or ask git
   (`git rev-parse --show-toplevel`) for the enclosing repo and look for
   `industrial-edge-insights-multimodal/Makefile`.
   `cd` into that directory before running any command below — the Makefile
   and the helper scripts read `.env` from the current directory.
2. Confirm `.env` exists and the credentials checked by
   `make check_env_variables` are set: `INFLUXDB_USERNAME/PASSWORD`,
   `VISUALIZER_GRAFANA_USER/PASSWORD`,
   `MTX_WEBRTCICESERVERS2_0_USERNAME/PASSWORD`, `S3_STORAGE_USERNAME/PASSWORD`,
   `SEAWEEDFS_WEB_AUTH_USER/PASSWORD`. When deploying with `MCP=true`,
   `MCP_USERNAME` (letters only, 5+ characters) and `MCP_PASSWORD`
   (alphanumeric, 10+ characters, at least one letter and one digit) are also
   required; they are empty in the shipped `.env`. Do not invent
   credentials — ask the user for any that are unset.
3. Confirm `HOST_IP` in `.env` is a valid IPv4 address (default
   `127.0.0.1`). `localhost` is rejected by `make validate_host_ip`; use the
   host's LAN IP when the UI must be reachable from other machines.
4. Docker preflight: `docker info >/dev/null 2>&1`.

   If the preflight fails, **stop immediately**, report the host blocker, and
   give the exact command sequence the user would need to run themselves
   instead of waiting or retrying indefinitely.

## Step 1: Choose the variant

Ask (or infer from the user's request) which variant to deploy:

| Variant | Make target | Notes |
|---|---|---|
| Default (vision + time-series fusion) | `make up` | No extra hardware checks |
| vLLM-based VLM | `make up_vllm` | Requires `make check_hardware` + `make check_models` (models must already be in `configs/vllm/models` and `configs/vllm/huggingface`) |
| Agentic | `make up_agentic` | Requires `make check_hardware` + `make check_models`, then triggers `make download_model` (can take minutes) |
| Agentic + MCP server | `make up_agentic MCP=true` | Same as Agentic, plus `docker-compose-mcp.yml` (`multimodal-mcp-server`), `MCP_USERNAME`/`MCP_PASSWORD` validation, and the `agentic_mcp` nginx profile that exposes `/mcp`. Pipelines do **not** auto-start — see Step 2 |

All `up*` targets implicitly run `check_env_variables`, `validate_host_ip`,
and `down` first (see `references/command-reference.md`). `MCP=true` is
only honoured by `up_agentic` (and by `build`, `build_copyleft_sources`,
`down`, `push_images`); `make up MCP=true` and `make up_vllm MCP=true` do
not start the MCP server.

## Step 2: Build and deploy

```bash
make build                 # or: make build_copyleft_sources; add MCP=true to also build mcp-server
make up                    # or: make up_vllm / make up_agentic / make up_agentic MCP=true
make status                # containers + recent error-log scan
```

- `make up*` already calls `down` first, so no separate teardown is needed
  between iterations unless you want to fully reset.
- `make up*` uploads the UDF tar and posts the Time-Series Analytics config
  via `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/...` after the containers
  start; a failure there fails the target. Exception: `make up_agentic
  MCP=true` skips this step (see MCP mode below).
- Do not use `make -n` to preview `up*` targets. Their recipe lines contain
  `$(MAKE)`, so GNU Make still runs them (including `docker compose up -d`)
  in dry-run mode. Read the `Makefile` or `references/command-reference.md`
  instead.
- `make up_vllm`/`make up_agentic` will fail fast via `check_hardware` unless
  running on the required Intel Panther Lake / Core Ultra 3xx platform, or
  `PLATFORM_CHECK=false` is set (in `.env` or on the `make` command line) for
  CI/validation use.
- Report `make status` output verbatim; a container with recent `error` log
  lines is a real signal — don't suppress it.

### MCP mode (`make up_agentic MCP=true`)

- Pass `MCP=true` consistently: `make build MCP=true` builds the
  `multimodal-mcp-server` image (plain `make build` does not).
- The MCP overlay mounts `configs/dlstreamer-pipeline-server/config_auto_start_off.json`,
  so the weld classification pipeline does **not** auto-start, and
  `up_agentic` **skips** `upload_tar_file`/`post_config`. Right after
  deployment, no vision or time-series data is processed and Grafana stays
  empty — this is expected, not a failure.
- Processing starts only when an MCP client calls `start_pipeline`
  (optionally with `vision_inf_device` `CPU|GPU|NPU` and
  `time_series_inf_device` `CPU|GPU`). The tool uploads the UDF package,
  posts the Time-Series Analytics config, waits up to 120 s for the
  `weld_anomaly_detector` task, then starts the DL Streamer pipeline.
  `stop_pipeline` stops both. Both affect live processing — confirm with the
  user before calling them.
- The MCP endpoint is `https://${HOST_IP}:${GRAFANA_PORT}/mcp` (Streamable
  HTTP, stateless, behind nginx with the self-signed certificate). nginx does
  not add authentication to `/mcp`; the server requires HTTP Basic auth
  (`MCP_USERNAME`/`MCP_PASSWORD`) only for `start_pipeline` and
  `stop_pipeline`. The read-only tools (`describe`, `list_insights_data`,
  `explain`, `get_run_results`) and `run_agent` do not require credentials,
  so do not expose the gateway beyond a trusted network.
- The server also has plain-HTTP routes `/start_pipeline`, `/stop_pipeline`,
  and `/explain` on port 8000, but nginx proxies only `/mcp`; those routes
  are reachable only from the Docker network.

## Step 3: Smoke test

From the app root, run
`.github/skills/multimodal-deploy/scripts/smoke-check.sh`, which:
- verifies the Docker daemon is reachable,
- runs `make status`,
- curls the nginx/Grafana endpoint
  `https://${HOST_IP}:${GRAFANA_PORT}/` (values read from `.env`; `-k` for
  the self-signed cert) with retries,
- if the `multimodal-mcp-server` container is running, sends an MCP
  `tools/list` request to `https://${HOST_IP}:${GRAFANA_PORT}/mcp` and
  requires HTTP 200 with the `describe` tool in the response. This probe is
  read-only; it does not start or stop pipelines.

Report the script's pass/fail output directly to the user.

## Step 3b (MCP mode only): Exercise the MCP server

Use the bundled example client (it reads `MCP_USERNAME`, `MCP_PASSWORD`,
`HOST_IP`, and `GRAFANA_PORT` from the app-root `.env` and always sends the
Basic auth header):

```bash
cd mcp-server/example
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python example_client.py --insecure describe              # read-only
.venv/bin/python example_client.py --insecure start_pipeline \
    --vision-inf-device CPU --time-series-inf-device CPU            # starts live processing
.venv/bin/python example_client.py --insecure list_insights_data --page 1 --page-size 10
.venv/bin/python example_client.py --insecure run_agent --time-range 30s
.venv/bin/python example_client.py --insecure get_run_results --run-id <RUN_UUID>
.venv/bin/python example_client.py --insecure stop_pipeline         # stops live processing
```

`--insecure` is only for the bundled self-signed certificate; `--url
https://HOST:PORT/mcp` overrides the address from `.env`. Call
`start_pipeline`/`stop_pipeline`/`run_agent` only after the user confirms.
After `start_pipeline`, allow time for data to flow before expecting
results from `list_insights_data`.

To register the server in another MCP client (for example, an agent
harness `mcp_servers` entry), use URL
`https://${HOST_IP}:${GRAFANA_PORT}/mcp` and an
`Authorization: Basic <base64(MCP_USERNAME:MCP_PASSWORD)>` header. The
client must trust the nginx certificate (or use a trusted certificate that
matches the host). Never paste the real credentials into chat output or
committed files.

## Step 4: Functional tests

See `references/functional-tests.md` for the full file-to-hardware mapping.
Typical invocation (from `tests/functional/`, after
`pip install -r ../requirements.txt`):

```bash
pytest -v -s --html=docker_multimodal_report.html test_docker_deployment_multimodal.py
pytest -v -s -m gpu --html=gpu_docker_multimodal_report.html test_GPU_docker_multimodal.py
pytest -v -s --html=npu_docker_multimodal_report.html test_NPU_docker_multimodal.py
```

Or use `.github/skills/multimodal-deploy/scripts/run-functional-tests.sh [cpu|gpu|npu]`
to select the right subset automatically.

The tests deploy and tear down the stack themselves, and they **overwrite
`.env`**: credentials are replaced with generated test values and `HOST_IP` is
set to the system IP address. Tell the user before running them, and suggest
backing up `.env` first (for example, `cp .env .env.bak`). Summarize pytest's
pass/fail counts; do not just dump the raw HTML report path without a verdict.

The functional suites do not cover `MCP=true`; verify MCP mode with Step 3
and Step 3b instead.

## Step 5: Cleanup

```bash
make down                  # use: make down MCP=true after an MCP deployment
```

Mention that `make down` removes volumes (`-v`) — any InfluxDB/Grafana state
will be lost between iterations. `--remove-orphans` also removes the MCP
server container when `MCP=true` is omitted, but pass `MCP=true` to keep the
compose file set identical to the deploy.

## Answer contract when blocked

If Docker is unreachable, hardware checks fail, or required models are
missing, **do not stall**: state the blocker plainly, show the exact command
sequence the user would run once unblocked, and stop. Never invent "it
worked" output.
