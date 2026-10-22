---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: multimodal-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Multimodal Weld
  Defect Detection sample application (industrial-edge-insights-multimodal)
  via its Makefile-driven Docker Compose path. Use this skill for quick
  build/deploy/teardown cycles, variant selection (default, vLLM, agentic,
  agentic with the MCP server via `make up_agentic MCP=true`), meeting
  hardware/model prerequisites by following the app's docs/user-guide
  (including the vLLM model download), MCP endpoint checks, and running the
  existing tests/functional pytest suites. Do not use this skill for
  application code changes, unrelated components, or production rollout
  decisions.
license: Apache-2.0
compatibility: >-
  Requires a local checkout of industrial-edge-insights-multimodal (its
  Makefile, .env, and docs/user-guide are read at runtime; the skill can be
  installed anywhere, for example with `npx skills add`), a bash-compatible
  shell, Docker + Docker Compose v2, make, and curl. Functional tests additionally require Python 3 and the packages in
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

## Path resolution (the skill may be installed outside the repo)

This skill may live inside the repo
(`industrial-edge-insights-multimodal/.github/skills/multimodal-deploy/`) or
be installed standalone into an agent's skills directory (for example with
`npx skills add`, which copies only this skill folder). Paths in this skill
therefore use two bases:

| Base | Paths | How to resolve |
|---|---|---|
| **Skill directory** (`<skill-dir>`, the folder containing this `SKILL.md`) | `references/…`, `scripts/…`, `example-prompts/…` | Always bundled with the skill |
| **App root** (Step 0) | `Makefile`, `.env`, `configs/…`, `docs/user-guide/…`, `tests/…`, `mcp-server/…` | Read from the user's checkout at runtime; never expected inside `<skill-dir>` |

The user guide is intentionally **not** copied into the skill: it ships in
the same checkout as the `Makefile` the skill drives, so it always matches
the version being deployed. Only if `<app-root>/docs/user-guide/` is
missing (for example, an incomplete sparse checkout), fetch the page from
GitHub at the checkout's ref (the commit from `git -C <app-root> rev-parse
HEAD`, or `main` if the app root is not a git checkout):
`https://raw.githubusercontent.com/open-edge-platform/manufacturing-ai-suite/<ref>/industrial-edge-insights-multimodal/<path>`.
Say in your report that you used the remote copy.

## Normative references

### User guide (primary source for prerequisites and procedures)

The application's own user guide is the authoritative procedure for system
requirements, prerequisites, model downloads, and per-variant deployment.
**Read the relevant page and follow its commands as written** instead of
composing your own sequence. Paths are relative to the **app root**, not
the skill directory (see "Path resolution" for the remote fallback):

| Page | Use it for |
|---|---|
| `docs/user-guide/get-started/system-requirements.md` | Base hardware/OS/Docker/Python requirements for every variant |
| `docs/user-guide/get-started.md` | Docker configuration (non-root, proxy, log rotation), `.env` fields, default `make up` deploy, GPU/NPU inference switches, verification, `make status` caveats |
| `docs/user-guide/get-started/build-from-source.md` | `make build` / `make build_copyleft_sources` |
| `docs/user-guide/how-to-guides/how-to-deploy-vllm-service.md` | vLLM variant: extra hardware/RAM/storage requirements, the **Download Models** procedure that populates `configs/vllm/huggingface` and `configs/vllm/models`, `VLLM_GPU_MEMORY_UTILIZATION`, `make up_vllm`, verification, troubleshooting |
| `docs/user-guide/how-to-guides/how-to-deploy-agent-workflow.md` | Agentic variant (with or without `MCP=true`): extra requirements, prerequisites (including the vLLM model download), `LLM_DEVICE`, `make up_agentic [MCP=true]`, agent configuration, verification |
| `docs/user-guide/how-to-guides/how-to-update-config.md`, `how-to-configure-alerts.md`, `how-to-configure-rtsp-camera.md`, `how-to-access-s3-stored-images.md` | Post-deploy configuration questions |
| `docs/user-guide/troubleshooting.md` | Known runtime issues ("No Data" in Grafana, slow Time-Series Analytics start, coturn/mediamtx log noise, EMT `docker exec`) |

### Skill-local references (Makefile/test facts not covered by the user guide)

Relative to `<skill-dir>`:

- `references/command-reference.md` — Make target catalogue, including the
  `MCP` flag and MCP server tools. The live `Makefile` is the source of
  truth for gate behaviour; if the user guide and the `Makefile` disagree,
  follow the `Makefile` and mention the discrepancy in your report.
- `references/functional-tests.md` — mapping of test files to hardware.

## Step 0: Locate the app root and preflight

1. Resolve the app root (a directory containing `Makefile`,
   `docker-compose-agentic.yml`, and `fusion-analytics/`), in this order:
   a path the user gave; `$MULTIMODAL_APP_ROOT`; cwd or one of its parents;
   `<git toplevel>/industrial-edge-insights-multimodal` from
   `git rev-parse --show-toplevel`. Do not derive it from `<skill-dir>`.
   `cd` into that directory before running any command below — the Makefile
   and the helper scripts read `.env` from the current directory.
   If no checkout exists, stop and offer the **Clone source code** commands
   from `docs/user-guide/get-started.md` (fetch that page remotely, per
   "Path resolution"); its sparse checkout includes `docs/`.
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
   point the user to the **Configure Docker** section of
   `docs/user-guide/get-started.md` (non-root Docker, proxy) instead of
   waiting or retrying indefinitely.
5. Compare the host against
   `docs/user-guide/get-started/system-requirements.md` (OS, Docker version,
   Python, RAM, storage). Report shortfalls; they are warnings for the
   default variant, but see Step 1b for the stricter vLLM/agentic limits.

## Step 1: Choose the variant

Ask (or infer from the user's request) which variant to deploy:

| Variant | Make target | Procedure doc | Notes |
|---|---|---|---|
| Default (vision + time-series fusion) | `make up` | `docs/user-guide/get-started.md` | No extra hardware checks |
| vLLM-based VLM | `make up_vllm` | `docs/user-guide/how-to-guides/how-to-deploy-vllm-service.md` | Requires `check_hardware` + `check_models` — see Step 1b |
| Agentic | `make up_agentic` | `docs/user-guide/how-to-guides/how-to-deploy-agent-workflow.md` | Requires `check_hardware` + `check_models` (Step 1b), then triggers `make download_model` (can take minutes) |
| Agentic + MCP server | `make up_agentic MCP=true` | `docs/user-guide/how-to-guides/how-to-deploy-agent-workflow.md` | Same as Agentic, plus `docker-compose-mcp.yml` (`multimodal-mcp-server`), `MCP_USERNAME`/`MCP_PASSWORD` validation, and the `agentic_mcp` nginx profile that exposes `/mcp`. Pipelines do **not** auto-start — see Step 2 |

All `up*` targets implicitly run `check_env_variables`, `validate_host_ip`,
and `down` first (see `references/command-reference.md`). `MCP=true` is
only honoured by `up_agentic` (and by `build`, `build_copyleft_sources`,
`down`, `push_images`); `make up MCP=true` and `make up_vllm MCP=true` do
not start the MCP server.

## Step 1b: Meet variant prerequisites (from the user guide)

Read the **Minimum System Requirements** and **Prerequisites** sections of
the variant's procedure doc (table above) and satisfy them before running
any `up*` target. When the user asks you to "meet prerequisites", this
step is part of the job — do not stop at the first failing gate if the
documented procedure resolves it.

For `make up_vllm`, `make up_agentic`, and `make up_agentic MCP=true`:

1. **Hardware/platform.** Run `make check_hardware`. The docs require an
   Intel Core Ultra Series 3 processor or newer, at least 32 GB RAM, and at
   least 256 GB storage (512 GB recommended); check with `free -g` and
   `df -h .` and report any shortfall. `PLATFORM_CHECK=false` bypasses only
   the CPU gate and is for CI/validation, not for real deployments.
2. **vLLM base model and LoRA adapter.** Run `make check_models`. If it
   fails (`configs/vllm/models` or `configs/vllm/huggingface` missing or
   empty), follow **Download Models** in
   `docs/user-guide/how-to-guides/how-to-deploy-vllm-service.md` exactly —
   run its command block from the app root (it creates a throwaway
   `configs/vllm/.modelenv` venv, installs the pinned `huggingface_hub`, and
   runs `hf download` for the base model and the weld LoRA adapter). Then
   re-run `make check_models` and require it to pass.
   - The doc asks the user to review and accept the base model's license
     first. Show the license link from the doc; proceed only if the user
     already explicitly asked you to download models or meet prerequisites,
     otherwise ask first.
   - `make download_model` (run inside `up_agentic`) does **not** satisfy
     this gate: it fetches the agentic LLM (`LLM_MODEL_NAME`) into
     `configs/agentic/models` via the `model-download` service, and
     `check_models` runs before it.
   - `configs/vllm*` is git-ignored; staged models are not tracked and
     survive `make down`.
   - Download failures (no network, proxy, disk full) are real blockers —
     report the failing `hf download` output and stop.
3. **Device/memory settings.** Mention, but do not change unless asked,
   `VLLM_GPU_MEMORY_UTILIZATION` (vLLM doc) and `LLM_DEVICE` (`CPU`
   default, or `GPU`; agentic doc). Never edit `.env` without the user's
   permission.
4. **MCP credentials** (`MCP=true` only): `MCP_USERNAME`/`MCP_PASSWORD`
   must be set in `.env` (Step 0). If unset, name the missing variable and
   stop.

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
  lines is a real signal — don't suppress it. Per the user guide, Grafana
  `user token not found` errors before the first login are benign.
- Expect long first starts (from the user guide): `vllm-server` can take
  about 10 minutes to load the model, and `make download_model` polls for up
  to 50 minutes. Check `docker logs vllm-server` rather than re-running
  `up*`.
- For verification and stop steps, follow the variant's procedure doc
  (**Verify the Deployment** in the how-to guides, **Verify the Multimodal
  Weld Defect Detection Results** in `get-started.md`). For runtime issues, check
  `docs/user-guide/troubleshooting.md` and the doc's own **Troubleshooting**
  section before improvising a fix.

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

From the app root, run `<skill-dir>/scripts/smoke-check.sh` (or set
`MULTIMODAL_APP_ROOT` when running it from elsewhere), which:
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

Or run `<skill-dir>/scripts/run-functional-tests.sh [cpu|gpu|npu]` from the
app root to select the right subset automatically.

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

A failing prerequisite that the user guide documents how to fix (for example,
`check_models` failing because the vLLM models are not staged) is **not** a
blocker: apply the documented procedure (Step 1b), then continue.

Real blockers are conditions you cannot or must not fix yourself: Docker is
unreachable, `check_hardware` fails on unsupported hardware, a required
`.env` credential is unset, the model license has not been accepted, or a
documented download fails. In those cases, **do not stall**: state the
blocker plainly, cite the user-guide section that covers it, show the exact
command sequence the user would run once unblocked, and stop. Never invent
"it worked" output.
