---
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
name: multimodal-deploy
description: >-
  Build, deploy, smoke-check, and functionally test the Multimodal Weld
  Defect Detection sample application (industrial-edge-insights-multimodal)
  via its Makefile-driven Docker Compose path. Use this skill for quick
  build/deploy/teardown cycles, variant selection (default, vLLM, agentic),
  hardware/model prerequisite checks, and running the existing
  tests/functional pytest suites. Do not use this skill for application code
  changes, unrelated components, or production rollout decisions.
license: Apache-2.0
compatibility: >-
  Requires a bash-compatible shell, Docker + Docker Compose v2, make, and
  curl. Functional tests additionally require Python 3 and the packages in
  tests/requirements.txt. Helm/Kubernetes deployment is not supported.
metadata:
  author: open-edge-platform
  version: "1.0.0"
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
   `SEAWEEDFS_WEB_AUTH_USER/PASSWORD`. Do not invent credentials — ask the
   user for any that are unset.
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

All three targets implicitly run `check_env_variables`, `validate_host_ip`,
and `down` first (see `references/command-reference.md`).

## Step 2: Build and deploy

```bash
make build                 # or: make build_copyleft_sources
make up                    # or: make up_vllm / make up_agentic
make status                # containers + recent error-log scan
```

- `make up*` already calls `down` first, so no separate teardown is needed
  between iterations unless you want to fully reset.
- `make up*` uploads the UDF tar and posts the Time-Series Analytics config
  via `https://${HOST_IP}:${GRAFANA_PORT}/ts-api/...` after the containers
  start; a failure there fails the target.
- `make up_vllm`/`make up_agentic` will fail fast via `check_hardware` unless
  running on the required Intel Panther Lake / Core Ultra 3xx platform, or
  `PLATFORM_CHECK=false` is set (in `.env` or on the `make` command line) for
  CI/validation use.
- Report `make status` output verbatim; a container with recent `error` log
  lines is a real signal — don't suppress it.

## Step 3: Smoke test

From the app root, run
`.github/skills/multimodal-deploy/scripts/smoke-check.sh`, which:
- verifies the Docker daemon is reachable,
- runs `make status`,
- curls the nginx/Grafana endpoint
  `https://${HOST_IP}:${GRAFANA_PORT}/` (values read from `.env`; `-k` for
  the self-signed cert) with retries.

Report the script's pass/fail output directly to the user.

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

## Step 5: Cleanup

```bash
make down
```

Mention that `make down` removes volumes (`-v`) — any InfluxDB/Grafana state
will be lost between iterations.

## Answer contract when blocked

If Docker is unreachable, hardware checks fail, or required models are
missing, **do not stall**: state the blocker plainly, show the exact command
sequence the user would run once unblocked, and stop. Never invent "it
worked" output.
