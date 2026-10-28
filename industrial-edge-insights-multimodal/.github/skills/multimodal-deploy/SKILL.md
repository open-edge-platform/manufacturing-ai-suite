---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: multimodal-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Multimodal Weld
  Defect Detection sample application (industrial-edge-insights-multimodal)
  via its Makefile-driven Docker Compose path. Use this skill for quick
  build/deploy/teardown cycles, building the Time Series Analytics
  microservice from the latest source as in the user guide's Build from
  source page (only when the request explicitly asks for it), variant selection (default, vLLM, agentic,
  agentic with the MCP server via `make up_agentic MCP=true`), meeting
  hardware/model prerequisites by following the app's published user guide
  (including the vLLM model download), MCP endpoint checks, and running the
  existing tests/functional pytest suites. Do not use this skill for
  application code changes, unrelated components, or production rollout
  decisions.
license: Apache-2.0
compatibility: >-
  Requires a local checkout of industrial-edge-insights-multimodal (its
  Makefile, .env, configs, and tests are read at runtime; the skill itself
  can be installed anywhere), web access to the published user guide (or the
  checkout's docs/user-guide copy), bash, Docker + Docker Compose v2, make,
  curl, and git. Functional tests need Python 3 and tests/requirements.txt;
  the MCP example client needs Python 3 and
  mcp-server/example/requirements.txt. Helm/Kubernetes is not supported.
metadata:
  author: open-edge-platform
  tags: deployment, docker-compose, manufacturing, multimodal, weld-defect-detection
allowed-tools: bash, make, docker, pytest
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
therefore use three bases:

| Base | Paths | How to resolve |
|---|---|---|
| **Skill directory** (`<skill-dir>`, the folder containing this `SKILL.md`) | `references/…`, `scripts/…`, `example-prompts/…` | Always bundled with the skill |
| **App root** (Step 0) | `Makefile`, `.env`, `configs/…`, `tests/…`, `mcp-server/…` | Read from the user's checkout at runtime; never expected inside `<skill-dir>` |
| **User guide** | Pages linked under "Normative references" | Published at <https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/index.html>; page `<page>.html` there is also in the checkout as `docs/user-guide/<page>.md` |

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
requirements, prerequisites, model downloads, and per-variant deployment.
**Read the relevant page and follow its commands as written** instead of
composing your own sequence (see "Path resolution" for when to read the
checkout copy instead):

| Page | Use it for |
|---|---|
| [System requirements](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started/system-requirements.html) | Base hardware/OS/Docker/Python requirements for every variant |
| [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started.html) | Clone commands, Docker configuration (non-root, proxy, log rotation), `.env` fields, default `make up` deploy, GPU/NPU inference switches, verification, `make status` caveats |
| [Build from source](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started/build-from-source.html) | `make build` / `make build_copyleft_sources`, and, only when explicitly requested, building the Time Series Analytics microservice from the latest `edge-ai-libraries` source first (Step 2a) |
| [Deploy the vLLM service](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-vllm-service.html) | vLLM variant: extra hardware/RAM/storage requirements, the **Download Models** procedure that populates `configs/vllm/huggingface` and `configs/vllm/models`, `VLLM_GPU_MEMORY_UTILIZATION`, `make up_vllm`, verification, troubleshooting |
| [Deploy the agent workflow](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-agent-workflow.html) | Agentic variant (with or without `MCP=true`): extra requirements, prerequisites (including the vLLM model download), `LLM_DEVICE`, `make up_agentic [MCP=true]`, agent configuration, verification |
| [Update config](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-update-config.html), [Configure alerts](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-configure-alerts.html), [Configure an RTSP camera](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-configure-rtsp-camera.html), [Access S3-stored images](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-access-s3-stored-images.html) | Post-deploy configuration questions |
| [Troubleshooting](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/troubleshooting.html) | Known runtime issues ("No Data" in Grafana, slow Time-Series Analytics start, coturn/mediamtx log noise, EMT `docker exec`) |

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
   from [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started.html).
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
   [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started.html) (non-root Docker, proxy) instead of
   waiting or retrying indefinitely.
5. Compare the host against
   [System requirements](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started/system-requirements.html) (OS, Docker version,
   Python, RAM, storage). Report shortfalls; they are warnings for the
   default variant, but see Step 1b for the stricter vLLM/agentic limits.

## Step 1: Choose the variant

Ask (or infer from the user's request) which variant to deploy:

| Variant | Make target | Procedure doc | Notes |
|---|---|---|---|
| Default (vision + time-series fusion) | `make up` | [Get Started](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started.html) | No extra hardware checks |
| vLLM-based VLM | `make up_vllm` | [Deploy the vLLM service](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-vllm-service.html) | Requires `check_hardware` + `check_models` — see Step 1b |
| Agentic | `make up_agentic` | [Deploy the agent workflow](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-agent-workflow.html) | Requires `check_hardware` + `check_models` (Step 1b), then triggers `make download_model` (can take minutes) |
| Agentic + MCP server | `make up_agentic MCP=true` | [Deploy the agent workflow](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-agent-workflow.html) | Same as Agentic, plus `docker-compose-mcp.yml` (`multimodal-mcp-server`), `MCP_USERNAME`/`MCP_PASSWORD` validation, and the `agentic_mcp` nginx profile that exposes `/mcp`. Pipelines do **not** auto-start — see Step 2 |

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
   [Deploy the vLLM service](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-vllm-service.html) exactly —
   run its command block from the app root (it creates a throwaway
   `configs/vllm/.modelenv` venv, installs the pinned `huggingface_hub`, and
   runs `hf download` for the base model and the weld LoRA adapter). Then
   re-run `make check_models` and require it to pass.
   - **License acceptance.** The doc asks the user to review and accept the
     base model's license first. Show the license link from the doc and get
     explicit acceptance of that license before downloading. A request to
     "meet prerequisites" or "download models" is permission to download,
     not license acceptance — ask separately.
   - **Do not delete existing models.** The doc's block runs
     `rm -rf huggingface models`, which erases anything already staged
     (including user-supplied or git-ignored models/adapters). Before
     running it, list the contents of `configs/vllm/huggingface` and
     `configs/vllm/models`. If either is non-empty, do not run the `rm -rf`
     without the user's explicit permission; otherwise drop the `rm -rf`
     and run only the `hf download` for the missing directory.
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
<skill-dir>/scripts/build-time-series-analytics.sh   # ONLY if explicitly asked to build Time Series Analytics (Step 2a)
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
  [Troubleshooting](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/troubleshooting.html) and the doc's own **Troubleshooting**
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
  `stop_pipeline`. The read-only tools (`describe`, `get_pipeline_status`,
  `list_insights_data`, `explain`, `get_run_results`) and `run_agent` do not require credentials,
  so do not expose the gateway beyond a trusted network.
- The server also has plain-HTTP routes `/start_pipeline`, `/stop_pipeline`,
  and `/explain` on port 8000, but nginx proxies only `/mcp`; those routes
  are reachable only from the Docker network.

## Step 2a: Build the Time Series Analytics microservice from source (explicit request only)

This step is **conditional**. Run it only when the user's request explicitly
asks to build the Time Series Analytics microservice, for example "build the
Time Series Analytics microservice", "build Time Series Analytics from
source", or "build with the latest Time Series Analytics microservice".

Do **not** run it for any other build or deploy request: "build", "build
and deploy", "build from source", `make build`, `make build_copyleft_sources`,
or `make up_agentic MCP=true`. For those, run only `make build` (Step 2),
which builds the app images and keeps the published Time Series Analytics
image, because that compose service has no `build:` section. Do not infer the
request from symptoms (for example, a missing `/pipeline_status` route);
report the symptom and let the user ask for the build.

When the request does ask for it, follow steps 1 and 2 of
[Build from source](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/get-started/build-from-source.html),
from the app root (or with `MULTIMODAL_APP_ROOT` set):

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

MCP mode needs a Time Series Analytics image with the `/pipeline_status` and
`/stop_pipeline` routes, which `start_pipeline` and `stop_pipeline` call. Some
published images do not have them (the tools then fail with HTTP 404). To
check a running stack, look for `"/pipeline_status"` in
`curl -sk https://${HOST_IP}:${GRAFANA_PORT}/ts-api/openapi.json`. If it is
missing, report it and tell the user that building the Time Series Analytics
microservice from source (this step) and redeploying fixes it. Run the build
only if the user then explicitly asks for it.

## Step 3: Smoke test

From the app root, run `<skill-dir>/scripts/smoke-check.sh` (or set
`MULTIMODAL_APP_ROOT` when running it from elsewhere), which:
- verifies the Docker daemon is reachable,
- runs `make status`,
- curls the nginx/Grafana endpoint
  `https://${HOST_IP}:${GRAFANA_PORT}/` (values read from `.env`; `-k` for
  the self-signed cert) with retries,
- if the `multimodal-mcp-server` container is running, sends an MCP
  `tools/list` request (authenticated with `MCP_USERNAME`/`MCP_PASSWORD` from
  `.env`) to `https://${HOST_IP}:${GRAFANA_PORT}/mcp` and
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

The suites import shared helpers from the sibling
`industrial-edge-insights-time-series/tests` tree (`pytest.ini`
`pythonpath`). The **Clone source code** sparse checkout in Get Started
omits it, so collection fails. Before running tests, confirm
`../industrial-edge-insights-time-series/tests` exists; if not, add it from
the repository root with
`git sparse-checkout add industrial-edge-insights-time-series/tests`.

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
documented download or source build fails. In those cases, **do not stall**: state the
blocker plainly, cite the user-guide section that covers it, show the exact
command sequence the user would run once unblocked, and stop. Never invent
"it worked" output.
