<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Multimodal Weld Defect Detection — AI agents

## Canonical Instructions

Use this file as the canonical router for coding agents. Keep tool-specific
files such as `AGENTS.md`, `CLAUDE.md`, and `.cursor/rules/multimodal.mdc` as
short pointers to this file.

## What This App Is

The Multimodal Weld Defect Detection sample application fuses **vision**
(DL Streamer Pipeline Server) and **time-series** (Time-Series Analytics
Microservice) analytics to detect welding anomalies in real time. Fusion
analytics combines both signals with configurable `AND`/`OR` logic. It ships
as a Docker Compose stack (Helm/Kubernetes deployment is no longer supported)
and supports three variants: default (vision + time-series), vLLM-based VLM
inference, and an agentic VLM pipeline (optionally with an MCP server). Deeper user docs live under
[`docs/user-guide/`](../docs/user-guide/); this file is the agent-facing map.

## Deployment Modes

| Mode     | Make target     | Compose overlay                         | Notes |
|----------|------------------|------------------------------------------|-------|
| Default  | `make up`        | `docker-compose.yml`                      | Vision + time-series fusion, no extra hardware gate |
| vLLM     | `make up_vllm`   | `+ docker-compose-vllm.yml`               | Requires `make check_hardware` + `make check_models` (models pre-staged in `configs/vllm/models`, `configs/vllm/huggingface`) |
| Agentic  | `make up_agentic`| `+ docker-compose-agentic.yml` + vllm     | Requires `make check_hardware` + `make check_models`; runs `make download_model` first (downloads/converts the LLM, can take minutes) |
| Agentic + MCP | `make up_agentic MCP=true` | `+ docker-compose-mcp.yml` + agentic + vllm | As Agentic, plus `MCP_USERNAME`/`MCP_PASSWORD` validation and the `/mcp` nginx route. Pipelines do not auto-start; an MCP client starts them with `start_pipeline` |

All `up*` targets run `check_env_variables`, `validate_host_ip`, and `down`
first. `check_hardware` requires an Intel Panther Lake / Core Ultra 3xx CPU
unless `PLATFORM_CHECK=false` is set in `.env` or passed to `make` (CI/validation
use only).

**Use the `multimodal-deploy` skill** ([`.github/skills/multimodal-deploy/SKILL.md`](skills/multimodal-deploy/SKILL.md))
to drive build/deploy/smoke-test/functional-test cycles instead of running
raw commands ad hoc.

## Component Map

| Path | Purpose |
|------|---------|
| `Makefile` | All lifecycle targets (build, up/up_vllm/up_agentic, down, status, push_images) |
| `docker-compose.yml` | Default stack: DL Streamer Pipeline Server, Time-Series Analytics Microservice, fusion analytics, weld data simulator, InfluxDB, Grafana, MQTT broker, Telegraf, MediaMTX, coturn, SeaweedFS (master/volume/filer/S3), nginx |
| `docker-compose-vllm.yml` | vLLM overlay: `vllm-server` (VLM inference) + `multimodal-agentic-ui` |
| `docker-compose-agentic.yml` | Agentic overlay: `apm-agent`, `apm-llm`, `model-download`, `apm-metrics`, `prometheus` |
| `docker-compose-mcp.yml` | MCP overlay (`MCP=true`): `multimodal-mcp-server`; switches DL Streamer to `config_auto_start_off.json` |
| `mcp-server/` | FastMCP server (`server.py`) for pipeline control, fusion data, and agentic analysis; `example/` has a client |
| `.env` | Runtime configuration (credentials, `HOST_IP`, `GRAFANA_PORT`, LLM settings) — never commit real secrets |
| `configs/` | Per-service config: `agentic/`, `dlstreamer-pipeline-server/`, `grafana/`, `influxdb/`, `mqtt-broker/`, `nginx/`, `seaweedfs-s3/`, `telegraf/`, `time-series-analytics-microservice/` |
| `fusion-analytics/` | Fusion service combining vision + time-series anomaly signals (`fusion.py`, `api.py`) |
| `weld-data-simulator/` | Synthetic weld sensor data publisher for demo/testing |
| `ui-service/` | Web UI backend/frontend (`src/`, own `pytest.ini`) |
| `training/` | `classification-training/`, `vlm-fine-tuning/` — offline model training, not part of the runtime stack |
| `tests/functional/` | pytest suites for Docker Compose deployment (CPU/GPU/NPU variants) |
| `docs/user-guide/` | Get-started, build-from-source, vLLM/agentic deploy, alerts/config/RTSP/S3 how-tos, troubleshooting |

## Key Environment Variables (`.env`)

- `HOST_IP` (default `127.0.0.1`; must be a valid IPv4 address — `localhost`
  is rejected by `make validate_host_ip`), `GRAFANA_PORT` (default `3000`)
- `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD`,
  `MTX_WEBRTCICESERVERS2_0_USERNAME/PASSWORD`, `S3_STORAGE_USERNAME/PASSWORD`,
  `SEAWEEDFS_WEB_AUTH_USER/PASSWORD` — all validated by
  `make check_env_variables` (length/charset rules)
- `PLATFORM_CHECK` — set `false` to skip the Panther Lake hardware gate (CI only)
- `LLM_DEVICE`, `LLM_WEIGHT_FORMAT`, `LLM_MODEL_NAME` — vLLM/agentic model selection
- `MCP_USERNAME/PASSWORD` — MCP server Basic auth for `start_pipeline` and
  `stop_pipeline`; empty by default, validated only with `MCP=true`
- `DOCKER_REGISTRY`, `IMAGE_SUFFIX`, `WEEKLY_BUILD_DATE` — push/versioning
- `HOST_UID`, `HOST_GID` — exported by Make (invoking user) for vLLM, OVMS, and model
  download; export them for direct Compose. Repair model-directory ownership; never `chmod 777`.

## Useful Commands

```bash
make build                # Build Docker images (add build_copyleft_sources for copyleft sources)
make up                   # Default variant
make up_vllm              # vLLM/VLM variant (hardware + model checks first)
make up_agentic           # Agentic variant (hardware check + model download first)
make up_agentic MCP=true  # Agentic variant + MCP server at https://HOST_IP:GRAFANA_PORT/mcp
make status               # Container status + recent error-log scan
make down                 # Stop and remove containers + volumes (add MCP=true after an MCP deploy)
make push_images          # Build then push to DOCKER_REGISTRY
make help                 # Command list from the Makefile
```

See [`.github/skills/multimodal-deploy/references/command-reference.md`](skills/multimodal-deploy/references/command-reference.md)
for the full, normative target/flag catalogue.

## Keeping Agent Guidance in Sync

**This file and the `multimodal-deploy` skill must be updated whenever the
Makefile, compose files, `.env` schema, functional tests, or
`docs/user-guide/` content change.** Make the update in the same pull request.
Skill paths below are relative to `.github/skills/multimodal-deploy/`.

| If the change touches… | Also update… |
|---|---|
| Make targets, flags, or target prerequisites | Deployment Modes and Useful Commands (this file); `references/command-reference.md`; `make help` text; user-guide steps that run the target |
| Compose services, overlays, or ports | Component Map (this file); `references/command-reference.md`; `scripts/smoke-check.sh` |
| `.env` keys, or `check_env_variables` / `validate_host_ip` rules | Key Environment Variables (this file); `SKILL.md` Step 0; get-started guide |
| Files, markers, or fixtures in `tests/functional/` | `references/functional-tests.md`; `scripts/run-functional-tests.sh`; `SKILL.md` Step 4 |
| Endpoints, URLs, or `HOST_IP` handling | `scripts/smoke-check.sh`; `SKILL.md` Steps 2–3 |
| A removed or renamed feature, file, or target | Every remaining reference (find them with `git grep`); keep historical entries in `CHANGELOG.md` and release notes unchanged |
| A skill's purpose or scripts | `.github/skills/README.md` catalog table; `.github/skills/skill-catalog.json` description and triggers |

Stale agent guidance is worse than none — treat these docs as part of the
change whenever you touch deployment-affecting files.

## Pre-Commit Checks

The repository has no `.pre-commit-config.yaml`. CI runs the scans in
`.github/workflows/industrial-edge-insights-time-series-scans.yml` (Pylint,
Bandit, ShellCheck, Trivy, CodeQL) and the PR workflow on changes to this
directory. Run the local equivalents before each commit, so that you find
problems before CI does.

1. Install the tools: `pip install pylint bandit`, and `shellcheck` from your
   OS package manager.
2. From the app root (`industrial-edge-insights-multimodal/`), run the checks
   on the staged files:

   ```bash
   git diff --cached --check
   git diff --cached --name-only --relative --diff-filter=ACMR -- '*.sh' | xargs -r shellcheck
   git diff --cached --name-only --relative --diff-filter=ACMR -- '*.py' | xargs -r pylint
   git diff --cached --name-only --relative --diff-filter=ACMR -- '*.py' | xargs -r bandit -q
   git diff --cached --name-only --relative --diff-filter=ACMR -- '*.json' | xargs -r -n1 python3 -m json.tool >/dev/null
   ```

3. Fix the findings in the lines that you changed. Findings in older code
   do not make new findings acceptable.
4. Make sure that `git diff --cached -- .env` shows no credentials. `.env`
   is tracked with blank credentials, and the functional tests write
   generated credentials into it. If you did not intend to change `.env`,
   run `git restore --staged --worktree .env`.
5. Add the SPDX header to each new program source file, but not to
   documentation such as Markdown (see the repository-root
   `.github/copilot-instructions.md`).

Do not use `git commit --no-verify` to skip hooks. If a
`.pre-commit-config.yaml` is added later, run
`pre-commit run --files <changed files>` and update this section.

## Commit Messages

Follow `CONTRIBUTING.md` and the format in the git history:

```text
<type>(<scope>): <Summary in the imperative mood>

<Why the change is necessary. One to three sentences.>

Changes:
- <One line for each logical change>

Signed-off-by: Your Name <your.name@example.com>
```

- `<type>`: `feat`, `fix`, `docs`, `test`, `ci`, `chore`, or `refactor`.
- `<scope>`: `multimodal`. Use `multimodal,time-series` when one commit
  changes both apps.
- Summary: use the present tense ("Add", not "Added"), and start with a
  capital letter. Do not end it with a period. Aim for 50 characters, and do
  not go over 72 characters for the full subject line.
- Body: wrap lines at 72 characters. Explain why. The diff already shows what.
- Sign off each commit with `git commit -s`. The Developer Certificate of
  Origin (DCO) sign-off is mandatory.
- Make one logical change in each commit. Do not mix a refactor with a
  behavior change.
- Do not put credentials, internal hostnames, or customer data in a commit
  message.
- Agents: commit only when the user asks.

## Code Review

Copilot code review comments only on the lines in the diff. It does not
report files that should have changed but did not. The author (in a
self-review) and the human reviewer must also look for missed updates.

Before you request a review, and again before you approve:

1. List the changed files: `git diff --name-only origin/main...HEAD -- .`
2. For each changed area, find its row in the table in
   [Keeping Agent Guidance in Sync](#keeping-agent-guidance-in-sync). Make
   sure that the PR also changes each file in the "Also update" column, or
   that the PR description says why no change is necessary.
3. Search for stale references to each renamed or removed item:
   `git grep -n -i '<old name>' -- .`
4. Run the smoke check and the functional tests that cover the change. Put
   the results in the PR description.
5. If the change touches Dockerfiles, compose files, secrets,
   authentication, input parsing, or CI workflows, also run the
   repository-root `.github/skills/security-review/SKILL.md` skill.
6. Check the other app. `tests/functional/pytest.ini` imports test utilities
   from `../../../industrial-edge-insights-time-series/tests/`. A change
   there can break the tests in this app.
7. For each Copilot or human comment, fix the problem or reply with the
   reason that you did not. Do not resolve a thread without a fix or a reply.

## Pull Requests

Complete each section of the repository-root
`.github/PULL_REQUEST_TEMPLATE.md`:

| Template section | What to write |
|---|---|
| Title | The commit summary format: `<type>(<scope>): <Summary>` |
| Description | What changed and why, in two to five sentences. Add `Fixes #<issue>` if an issue exists. List the agent-guidance files that you updated, or say why no update is necessary. |
| Any Newly Introduced Dependencies | The name, version, license, and use of each new third-party package or container image. If there are none, write "None". |
| How Has This Been Tested? | The exact commands, the variant (default, vLLM, or agentic), the hardware (CPU, GPU, or NPU), and the pass/fail counts. Say what you did not test, and why. |
| Checklist | Select an item only when it is true. |

- Keep one topic in each PR. Put unrelated changes in a different PR.
- Open the PR as a draft until the local checks pass.
- Do not paste `.env` contents, credentials, or logs that contain secrets.

## Writing Documentation (ASD-STE100)

Write user docs, agent guidance, commit bodies, and PR descriptions in the
style of ASD-STE100 Simplified Technical English (STE). The aerospace
industry uses STE for aircraft maintenance documentation, where a
misunderstood instruction can cause an accident. STE makes text clear for
readers whose first language is not English, and for AI agents. The
specification is available from <https://www.asd-ste100.org/>. The rules
below are a summary for this project. They are not the full standard.

- Write a maximum of 20 words in each procedural sentence and 25 words in
  each descriptive sentence.
- Write a maximum of six sentences in each paragraph. Give each paragraph
  one topic.
- Write procedures as numbered steps. Start each step with a verb in the
  imperative ("Run", "Set", "Open"). Give one instruction in each step,
  unless the actions occur at the same time.
- Use the active voice. Say who or what does the action.
- Use only the simple tenses: present, past, and future.
- Use one word for one meaning, and one term for one thing. For example,
  always write "Time-Series Analytics Microservice". Do not also call it
  "TSAM" or "the analytics service" in the same document. Define each
  abbreviation when you first use it.
- Do not put more than three nouns in a row. Write "the template for the
  nginx configuration", not "nginx proxy configuration file template".
- Keep articles ("a", "the") and short words. Do not remove words only to
  make a sentence shorter.
- Put a warning or caution before the step that it applies to. Start it with
  a command, then give the risk. Example: "**Caution:** Back up `.env`
  before you run the functional tests. The tests replace the credentials in
  `.env`."
- Use vertical lists for sequences and for more than three items.
- Put commands, file paths, Make targets, and env vars in code format. Use
  the exact name from the source file.

Example:

> **Before:** "Once the .env has been properly configured with all of the
> required credentials, the stack can be brought up via make up, which may
> take a while depending on your network."
>
> **After:** "Set all the required credentials in `.env`. Then run `make up`.
> This step can take several minutes on a slow network."

The documentation check (`.github/workflows/documentation-check.yaml`) builds
`docs/user-guide/` and checks spelling and links. Add new technical terms to
`docs/dictionary_append.txt`. Add external links that the link check cannot
reach to `docs/linkcheck_ignore_append.txt`.
