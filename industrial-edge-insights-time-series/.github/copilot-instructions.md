<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Industrial Edge Insights - Time Series — AI agents

## Canonical Instructions

Use this file as the canonical router for coding agents. Keep tool-specific
files such as `AGENTS.md`, `CLAUDE.md`, and `.cursor/rules/time-series.mdc`
as short pointers to this file.

## What This App Is

Industrial Edge Insights - Time Series demonstrates time-series anomaly
detection use cases, currently **wind turbine anomaly detection**, by
ingesting sensor data via **MQTT** or **OPC-UA**, running it through a
Time-Series Analytics Microservice (TICKscript/UDF-based), storing results in
InfluxDB, and visualizing them in Grafana. It ships as a Docker Compose stack
(Helm/Kubernetes deployment is no longer supported). The repo is structured to
support additional sample apps under `apps/` in the future (today only
`wind-turbine-anomaly-detection` is registered). Deeper user docs live under
[`docs/user-guide/`](../docs/user-guide/); this file is the agent-facing map.

## Deployment Modes

| Mode | Make target | Notes |
|------|-------------|-------|
| MQTT ingestion | `make up_mqtt_ingestion app=<name>` | `TELEGRAF_INPUT_PLUGIN=mqtt_consumer`; scales `ia-mqtt-publisher` to `num_of_streams` |
| OPC-UA ingestion | `make up_opcua_ingestion app=<name>` | `TELEGRAF_INPUT_PLUGIN=opcua`; scales `ia-opcua-server` to `num_of_streams` |
| Batch | append `batch` goal, e.g. `make up_mqtt_ingestion batch app=<name>` | Uses `config-batch.json` instead of `config.json` for the Time-Series Analytics Microservice |
| Validation | add `INCLUDE=validation`, e.g. `make up_mqtt_ingestion INCLUDE=validation` | Adds `docker-compose-validation.override.yml` (system-metrics dashboard + extra Telegraf inputs); ignores `num_of_streams` instance scaling |
| MCP control | add `MCP=true` to either ingestion target | Adds `docker-compose-mcp.yml`; analytics waits for authenticated `start_pipeline`. Supports batch and validation overlays |

`app` defaults to `wind-turbine-anomaly-detection` (must match
`SAMPLE_APP_LIST` in the `Makefile`). Both `up_*` targets run
`check_env_variables` and `down` first.

**Use the `time-series-deploy` skill**
([`.github/skills/time-series-deploy/SKILL.md`](skills/time-series-deploy/SKILL.md))
to drive build/deploy/smoke-test/functional-test cycles instead of running
raw commands ad hoc.

## Component Map

| Path | Purpose |
|------|---------|
| `Makefile` | All lifecycle targets (build, up_mqtt_ingestion/up_opcua_ingestion, down, status, push_images) |
| `docker-compose.yml` | Stack: Time-Series Analytics Microservice, InfluxDB, Grafana, MQTT broker, Telegraf, MQTT publisher, OPC-UA server, nginx |
| `docker-compose-validation.override.yml` | CI/validation overlay (`INCLUDE=validation`): system-metrics Grafana dashboard + host-metric Telegraf inputs |
| `docker-compose-mcp.yml`, `mcp-server/` | Optional authenticated FastMCP server, example client, and locked Python dependencies |
| `.env` | Runtime configuration (credentials, `HOST_IP`, `GRAFANA_PORT`) — never commit real secrets |
| `configs/` | Per-service config: `grafana/`, `influxdb/`, `mqtt-broker/`, `nginx/`, `telegraf/` |
| `apps/<app>/` | Per-sample-app assets: `grafana-dashboard.json`, `time-series-analytics-config/`, `telegraf-config/`, `training/`, `simulation-data/` |
| `simulator/` | `mqtt-publisher/`, `opcua-server/` — synthetic sensor data generators |
| `generate-telegraf-config.py` | Regenerates multi-stream Telegraf config when `num_of_streams > 1` |
| `tests/functional/` | pytest suites for Docker Compose deployment, retention, stability, security, GPU |
| `docs/user-guide/` | Get-started, build-from-source, alerts/config/custom-UDF/multi-stream/benchmarking how-tos, troubleshooting |

## Key Environment Variables (`.env`)

- `HOST_IP` (default `127.0.0.1`) — every Makefile call to the
  Time-Series Analytics Microservice goes to `https://${HOST_IP}:${GRAFANA_PORT}`
- `GRAFANA_PORT` (default `3000`)
- `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD` — validated
  by `make check_env_variables` (length/charset rules)
- `DOCKER_REGISTRY`, `IMAGE_SUFFIX`, `WEEKLY_BUILD_DATE` — push/versioning
- `MCP_USERNAME`, `MCP_PASSWORD` — required with `MCP=true`; username excludes
  `:`, maximum 128 characters; password length 10–1024 characters.
- `TIME_SERIES_MCP_IMAGE` — optional MCP image repository, default
  `industrial-edge-insights-time-series-mcp`; tag `2026.1.0`.
- MCP backend settings are supplied by the overlay. Native Kapacitor task APIs
  support status/stop on images without microservice control endpoints.

## Useful Commands

```bash
make build                           # Build Docker images (add build_copyleft_sources for copyleft sources)
make up_mqtt_ingestion app=<name>    # MQTT ingestion path
make up_opcua_ingestion app=<name>   # OPC-UA ingestion path
make status                          # Container status + recent error-log scan
make down                            # Stop and remove containers + volumes
make push_images                     # Build then push to DOCKER_REGISTRY
make help                            # Full command list from the Makefile
make build MCP=true                  # Also build the MCP image
make up_mqtt_ingestion MCP=true       # Deploy with analytics controlled by MCP
make down MCP=true                   # Remove an MCP deployment
```

For MCP setup, verified TLS, tool contracts, and lifecycle warnings, read
[`docs/user-guide/how-to-guides/use-mcp-server.md`](../docs/user-guide/how-to-guides/use-mcp-server.md).
Focused MCP tests live in `tests/mcp/`; use their instructions in `tests/README.md`.

See
[`.github/skills/time-series-deploy/references/command-reference.md`](skills/time-series-deploy/references/command-reference.md)
for the full, normative target/flag catalogue.

## Keeping Agent Guidance in Sync

**This file and the `time-series-deploy` skill must be updated whenever the
Makefile, compose files, `.env` schema, `apps/` sample-app list, functional
tests, or `docs/user-guide/` content change.** Make the update in the same pull request.
Skill paths below are relative to `.github/skills/time-series-deploy/`.

| If the change touches… | Also update… |
|---|---|
| Make targets, flags, or target prerequisites | Deployment Modes and Useful Commands (this file); `references/command-reference.md`; `make help` text; user-guide steps that run the target |
| A sample app in `apps/` or in `SAMPLE_APP_LIST` | Deployment Modes (this file); `SKILL.md` Step 1; App selection in `references/command-reference.md`; `docs/user-guide/how-to-guides/create-a-new-sample-app.md` |
| Compose services, overlays, or ports | Component Map (this file); `references/command-reference.md`; `scripts/smoke-check.sh` |
| `.env` keys or `check_env_variables` rules | Key Environment Variables (this file); `SKILL.md` Step 0; get-started guide |
| Files, markers, or fixtures in `tests/functional/` | `references/functional-tests.md`; `scripts/run-functional-tests.sh`; `SKILL.md` Step 4 |
| Endpoints, URLs, or `HOST_IP` handling | `scripts/smoke-check.sh`; `SKILL.md` Steps 0 and 3 |
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
2. From the app root (`industrial-edge-insights-time-series/`), run the checks
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
- `<scope>`: `time-series`. Use `multimodal,time-series` when one commit
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
6. Check the other app. The multimodal app's `tests/functional/pytest.ini`
   imports test utilities from `tests/` in this app. A change in `tests/`
   here can break the multimodal tests.
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
| How Has This Been Tested? | The exact commands, the ingestion path (MQTT or OPC-UA), any mode options (`batch`, `num_of_streams`), the hardware (CPU or GPU), and the pass/fail counts. Say what you did not test, and why. |
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
> required credentials, the stack can be brought up via
> make up_mqtt_ingestion, which may take a while depending on your network."
>
> **After:** "Set all the required credentials in `.env`. Then run
> `make up_mqtt_ingestion`. This step can take several minutes on a slow
> network."

The documentation check (`.github/workflows/documentation-check.yaml`) builds
`docs/user-guide/` and checks spelling and links. Add new technical terms to
`docs/dictionary_append.txt`. Add external links that the link check cannot
reach to `docs/linkcheck_ignore_append.txt`.
