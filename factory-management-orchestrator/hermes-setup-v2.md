# Hermes Agent v2: Deploy the Multimodal Weld Defect Detection App on Two Nodes from a Central Hermes

This guide uses one central [Hermes Agent](https://github.com/NousResearch/hermes-agent) to deploy the **Multimodal Weld Defect Detection** sample app (`industrial-edge-insights-multimodal`) on two edge nodes with:

```bash
make up_agentic MCP=true
```

The `multimodal-deploy` skill that ships with the app runs the deployment on each node and brings up the app together with its MCP server (`multimodal-mcp-server`). The central Hermes then connects to both MCP servers, so you can check, start, stop, and query weld analysis on either node from one place.

For Hermes installation, MCP basics, and CLI reference, see [hermes-setup.md](hermes-setup.md) (v1).

**Contents**

1. [Architecture](#1-architecture)
2. [Prerequisites](#2-prerequisites)

**Automated setup**

- [Quick start: one script for everything](#quick-start-one-script-for-everything)

**Manual setup** (the same steps, one at a time)

3. [Prepare the nodes](#3-prepare-the-nodes)
4. [Create one Hermes profile per node](#4-create-one-hermes-profile-per-node)
5. [Install the `multimodal-deploy` skill](#5-install-the-multimodal-deploy-skill)
6. [Deploy the app and MCP servers](#6-deploy-the-app-and-mcp-servers)
7. [Connect both MCP servers to the central Hermes](#7-connect-both-mcp-servers-to-the-central-hermes)

**Operations** (both paths)

8. [Verify and operate](#8-verify-and-operate)
9. [One command for the whole fleet](#9-one-command-for-the-whole-fleet)
10. [Tear down](#10-tear-down)
11. [Troubleshooting](#11-troubleshooting)
12. [Security notes](#12-security-notes)

**Orchestrator-based setup** (alternative, chat-driven)

13. [Manage the fleet with the MCP Fleet Orchestrator](#13-manage-the-fleet-with-the-mcp-fleet-orchestrator)

**What changed from v1**

| v1 | v2 |
| --- | --- |
| Example Flask app and a hand-written `node_ops_server.py` | The real multimodal app and its own `multimodal-mcp-server` |
| Custom deploy tools exposed over MCP | Deployment runs through the shipped `multimodal-deploy` skill over an SSH terminal backend |
| Plain HTTP MCP on each node | HTTPS MCP behind the app's nginx (`/mcp`), reached through an SSH tunnel |
| Tool names written as `mcp_<server>_<tool>` | Current Hermes names MCP tools `mcp__<server>__<tool>` |

---

## 1. Architecture

```text
Central Hermes host                                   weld-node-1
┌─────────────────────────────────────┐    SSH      ┌──────────────────────────────────────────┐
│ profile weld-node-1 (terminal: ssh) ├────────────►│ make up_agentic MCP=true                 │
│   skill: multimodal-deploy          │             │   nginx_proxy 127.0.0.1:3000 ─► /mcp     │
│                                     │  tunnel     │   multimodal-mcp-server                  │
│ default profile                     │  13001 ───► │   DL Streamer, TS analytics, vLLM, UI…   │
│   mcp_servers.weld_node1 ───────────┤             └──────────────────────────────────────────┘
│   mcp_servers.weld_node2 ───────────┤  tunnel     weld-node-2 (same stack)
│   skill: weld-fleet                 │  13002 ───►
│ profile weld-node-2 (terminal: ssh) ├────────────►
└─────────────────────────────────────┘
```

| Component | Runs on | Purpose |
| --- | --- | --- |
| Hermes, LLM API keys, all skills | Central host only | Orchestration |
| Profiles `weld-node-1`, `weld-node-2` | Central host | Each runs terminal commands on its node over SSH, so `multimodal-deploy` executes `make` on that node |
| Default profile | Central host | Holds the two MCP server registrations (`weld_node1`, `weld_node2`) and the `weld-fleet` skill |
| App stack + `multimodal-mcp-server` | Each node | Started by `make up_agentic MCP=true` |
| SSH tunnels `13001`, `13002` | Central host → node `127.0.0.1:3000` | Reach the node's nginx (`/mcp` and the UI) without exposing it on the network |

The nodes keep `HOST_IP=127.0.0.1`, so nginx listens only on the node's loopback interface. The central host reaches it through the SSH tunnel, and the nginx certificate (`CN=localhost`) matches `https://localhost:<tunnel-port>`.

---

## 2. Prerequisites

The automated script checks or installs most of these; the table shows what you still provide yourself.

| Requirement | Automated setup | Manual setup |
| --- | --- | --- |
| Hermes installed with an LLM provider on the central host ([v1, section 1](hermes-setup.md#1-installation-and-initial-setup)) | You provide | You provide |
| Central host: Linux with systemd user services, `ssh`, `curl`, `openssl`, `git` | Checked | You provide |
| Key-based SSH from the central host to each node | Installs your key (asks for the node password once) | You provide |
| Node: an account for the deployment, for example `deploy` | You provide | You provide |
| Node: `make`, `curl`, `git`, Docker Engine, Docker Compose v2 | Installed with `apt` if missing (asks for `sudo` once) | You provide |
| Node: deployment user in the `docker` group | Added if missing (asks for `sudo` once) | You provide |
| Node: app clone and `.env` credentials | Cloned; empty credentials filled with random valid values | You provide |
| Node: Intel Panther Lake / Core Ultra 3xx hardware | You provide | You provide |
| Node: network access to pull images and download the LLM | You provide | You provide |

Notes:

- Membership in the `docker` group is root-equivalent; use a dedicated account.
- The agentic target runs `make check_hardware` and fails on other hardware. `PLATFORM_CHECK=false` skips the check and is meant for CI/validation only.
- The first `make up_agentic` runs `make download_model`, which can take several minutes.
- Automatic package installation supports `apt`-based nodes (Ubuntu, Debian). On other distributions, install the node packages yourself first.
- Run the script as the central-host user from a normal login/SSH session.
  If the user-service check fails, the script retries with that user's existing,
  owned `/run/user/<uid>/bus` socket. It does not start a user manager or use
  `sudo`. If the retry fails, it shows the systemd error and stops. Ask an
  administrator to run `loginctl enable-linger <central-host-user>` if needed,
  then log in again.

---

## Quick start: one script for everything

`weld-fleet-setup.sh` runs on the central host. The recommended
[recipe inventory](#deployment-recipes-and-node-assignments) supports different
skills and multiple apps/MCP servers on each node, without editing the script.
The original node-only YAML and positional IP syntax remain supported for the
fixed weld deployment described in sections 3–7.

### Deployment recipes and node assignments

Keep [weld-fleet-setup.sh](weld-fleet-setup.sh) and its
[fleet_inventory.py](fleet_inventory.py) helper in the same directory. The
central host needs Python 3 and PyYAML (`sudo apt-get install python3-yaml`).
The helper validates the whole inventory before making changes and dispatches
each selected node/recipe assignment to an isolated setup run.

Start with [hosts.example.yaml](hosts.example.yaml), which contains the complete
weld recipe. Put your own recipes under `recipes`, then select them in each
node's `deployments`. [hosts.yaml](hosts.yaml) is the working inventory.

This minimal, illustrative recipe shows the structure for another app; replace
the repository, paths, prompt, ports, and tool names with that app's actual values
before running it:

```yaml
recipes:
  inspection:
    repository: https://github.com/your-org/inspection-app.git
    ref: v1.0.0
    remote_root: inspection-checkout
    app_dir: app
    skill:
      name: inspection-deploy
      path: .github/skills/inspection-deploy
      # Optional repository/ref here fetch the skill from a separate repository.
    prompt: >-
      In ~/inspection-checkout/app, use inspection-deploy to deploy the app
      and its MCP server, then run its documented smoke check.
      Ask for any required license acceptance. Do not start live processing.
    approval_policy: ESCALATE every terminal command.
    environment:
      set:
        HOST_IP: "127.0.0.1"
    mcp:
      scheme: http
      port: 8080
      path: /mcp
      auth:
        type: none
      tools: [describe]

defaults:
  user: deploy
  port: 22
  identity_file: ~/.ssh/weld_fleet_ed25519

nodes:
  - name: node1
    host: 192.168.1.21
    deployments:
      - recipe: inspection
        name: node1_inspection
        local_port: 14001
```

To install another skill/app on the same node, define another recipe and add
another item to that node's `deployments`. Assigning the same recipe on a
different node installs it there instead. The skill is installed in a **central
Hermes profile**, whose terminal backend runs commands over SSH on the chosen
node; no Hermes daemon is installed on the node.

| Field | Meaning |
| --- | --- |
| `recipes.<id>.repository`, `ref` | App HTTPS Git repository and branch/tag. Use a reviewed, pinned release ref where available |
| `source_delivery` | `central_copy` fetches app source on the Hermes host and sends a verified Git bundle to nodes; `node_clone` retains per-node upstream cloning (default for older recipes) |
| `remote_root` | Checkout directory relative to the node user's home; must be different for every app on that node |
| `app_dir` | App directory relative to the checkout (`.` for the repository root); traversal and absolute paths are rejected |
| `skill.name`, `skill.path` | Skill frontmatter name and directory relative to the skill repository. A matching `SKILL.md` is required |
| `skill.repository`, `skill.ref` | Optional separate HTTPS repository and branch/tag for the skill; default to the app repository/ref |
| `prompt` | Full app-specific deployment and verification instructions. Include the actual remote app path; no template or shell interpolation is performed |
| `approval_policy` | Hermes policy for this app only. Defaults to escalating every command; use an interactive first run |
| `environment.generate_users`, `generate_passwords` | Lists of `.env` variable names to fill with generated values only when empty; not secret values |
| `environment.set` | Non-secret, single-token `.env` settings to apply; names suggesting tokens/passwords/secrets are rejected. `HOST_IP`, if specified, must be loopback |
| `mcp.scheme`, `port`, `path` | `http` or `https`, remote loopback port, and MCP endpoint path. Node ports and central tunnel ports are separate |
| `mcp.certificate.path` | Required for HTTPS: absolute PEM certificate path on the node. Retrieved over SSH and pinned, not verification-disabled |
| `mcp.certificate.container` | Optional Docker container holding the certificate; omit to read the node filesystem |
| `mcp.auth.type` | `none`, `basic`, or `bearer`. Basic uses `username_key`/`password_key`; bearer uses `token_key`: names of existing/generated variables in the app's `.env`, never actual credentials |
| `mcp.tools` | Tool allow-list passed to Hermes. An empty list exposes no tools; explicitly list the app's documented tools |
| `nodes[].deployments[].recipe` | Named recipe to run on this node; several assignments are allowed |
| `nodes[].deployments[].name` | Stable MCP server/profile identity; defaults to `<node>_<recipe>`. Must be globally unique and at most 32 lowercase letters/digits/underscores |
| `nodes[].deployments[].local_port` | Required unique central tunnel port (1024–65535); remains stable when nodes are reordered |

Check and run only the desired assignments:

```bash
./weld-fleet-setup.sh --hosts hosts.yaml --list
./weld-fleet-setup.sh --hosts hosts.yaml --node node1 --recipe weld --list
./weld-fleet-setup.sh --hosts hosts.yaml --node node1 --recipe weld --interactive
```

Repeat `--node` or `--recipe` to select several; each selection type is ORed,
and node/recipe selections are intersected. Omit selectors to run every
assignment. Unknown selectors and empty selections are errors.

Recipe assignments run **sequentially** so two apps on one node do not race on
package setup or Docker access. A failure is recorded and remaining assignments
are attempted; the overall exit status is nonzero if any assignment fails.
Each assignment retains timestamped stage logging and its own deployment log.
Unlike legacy mode, a failed deployment in recipe mode remains a failure even
if a pre-existing MCP server is still reachable.

The runner currently supports Docker/Compose apps on apt-based nodes, with a
single `.env` in the configured app directory, and HTTP MCP endpoints reached
through SSH tunnels. It does not infer app ports, container names, prerequisite
commands, or authentication. You must supply those facts in the recipe and its
skill. Ensure each app binds its endpoint to loopback and has distinct host
ports, Docker container names, and Compose project/resources; the inventory
checks MCP port/checkout collisions but cannot discover all app resource
conflicts. HTTPS certificates must be valid for `localhost`, the tunnel host.
Unsupported formats fail rather than falling back to weld settings.

Treat recipes, skills, prompts, and approval policies as trusted executable
deployment configuration: review them before use. Keep all secrets on the node
or in the central protected credential file. TLS pins are read over SSH, and
basic/bearer credentials are referenced from the central Hermes environment,
not passed as command-line values. A `401` during the unauthenticated readiness
probe is only a sign that the endpoint is listening; the authenticated
`hermes mcp test` must still succeed.

#### Clone centrally and distribute to nodes

The working and example weld recipes now use:

```yaml
recipes:
  weld:
    source_delivery: central_copy
    # Other repository, skill, app, and MCP settings remain unchanged.
```

For each setup invocation, the Hermes host clones each selected app
repository/ref once into temporary storage, resolves the exact commit, and
creates a self-contained Git bundle with a SHA-256 checksum. Assignments with
the same repository/ref reuse that bundle, so they receive identical commits
even if the upstream branch changes during the run. Temporary central source
files are removed when the invocation finishes; a later invocation fetches again.

The bundle travels over SSH/SCP. Each node verifies its checksum, then clones
or fetches from the **local bundle**, without contacting the app's upstream
repository. Git metadata is retained so skills can inspect branches/commits;
the installed commit is checked and logged. The skill itself is still acquired
on the central host using its configured skill repository/ref.

Only committed app source/history is distributed, not the central host's
working directory, credentials, untracked files, or local model cache. A bundle
includes the selected branch/tag's history, so the transfer can be larger than a
source-only archive, especially for repositories with large committed files.
The remote checkout remains sparse for the configured app directory.

Existing Git checkouts are updated without a hard reset, clean, or forced
checkout. Per-node `.env`, model files, and generated data remain in place.
If the new commit conflicts with local source edits or untracked/ignored files,
Git stops rather than overwriting them; resolve those conflicts on the node
before retrying. An existing non-Git destination is also rejected. Source files
removed by the new commit are removed normally by Git; volumes are untouched.

`central_copy` currently rejects repositories using submodules or Git LFS;
choose `source_delivery: node_clone` for those repositories. Nodes still need
Git and network access for Docker images, packages, models, and any dependency
downloads performed by their skill. This setting only centralizes app source
delivery, not all deployment downloads.

### Legacy weld setup

The following steps and node-only schema describe the original fixed weld path.
In recipe mode, the recipe supplies the skill, checkout, prompt, credentials,
and MCP settings instead of these defaults. `SKILL_SRC`, `REPO_URL`, and
`REPO_BRANCH` environment overrides below apply only to legacy mode.

| Step | What the script does | Manual equivalent |
| --- | --- | --- |
| 1 | Checks this host for the required tools and systemd user services; creates an SSH key if you have none | [2](#2-prerequisites) |
| 2 | Fetches the `multimodal-deploy` skill (sparse clone of the `migrate/pr-4518` branch into `~/.cache/weld-fleet`) | [5](#5-install-the-multimodal-deploy-skill) |
| 3 | Creates profile `weld-node-N` per node: SSH backend to the node's host, user, port, and key, 3600 s command timeout, approval policy, and the `multimodal-deploy` skill | [4](#4-create-one-hermes-profile-per-node), [5](#5-install-the-multimodal-deploy-skill) |
| 4 | Per node: installs your SSH key (or the node's `identity_file`), installs missing packages, adds the user to the `docker` group, clones the app and checks out the `migrate/pr-4518` branch | [3](#3-prepare-the-nodes) |
| 5 | Fills empty credentials in the node's `.env` with random valid values (existing values are kept), pins `HOST_IP=127.0.0.1`, and stores the node's MCP login as `WELD_NODEN_MCP_BASIC` in `~/.hermes/.env` | [3](#3-prepare-the-nodes), [7.1](#71-store-the-mcp-credentials-on-the-central-host) |
| 6 | Runs the `multimodal-deploy` skill on all nodes in parallel: `make up_agentic MCP=true` and the smoke check | [6](#6-deploy-the-app-and-mcp-servers) |
| 7 | Per node: starts the SSH tunnel (`localhost:1300N`, or the node's `local_port`), fetches the nginx certificate, waits for `/mcp`, registers `weld_nodeN` in the central Hermes, and runs `hermes mcp test` | [7](#7-connect-both-mcp-servers-to-the-central-hermes) |

Secrets never pass through a Hermes chat or a command line: generated credentials are copied to the node as a file over SSH, and the MCP login is read back over SSH into `~/.hermes/.env` (mode `600`).

### Describe the nodes in `hosts.yaml`

Put the node list in `hosts.yaml` next to the script, or pass another file with `--hosts FILE`. A starting point is [hosts.example.yaml](hosts.example.yaml):

```yaml
defaults:
  user: deploy                               # same deployment account on every node
  port: 22
  identity_file: ~/.ssh/weld_fleet_ed25519   # created if missing; omit to use your default SSH key
  skip_platform_check: false

nodes:
  - name: weld_node1
    host: 192.168.1.21
  - name: weld_node2
    host: weld-line1-b.example.local
    port: 2222
    local_port: 13002
```

| Key | Where | Default | Meaning |
| --- | --- | --- | --- |
| `host` | node, required | — | IPv4 address or hostname |
| `name` | node | `weld_node<position>` | Node name used for the MCP server (`mcp__<name>__<tool>`), certificate, credential variable (`<NAME>_MCP_BASIC`), and log. `weld_nodeN` gets profile `weld-node-N`; other names get `_` replaced by `-` |
| `user` | defaults or node | `--user`, else `deploy` | SSH user on the node |
| `port` | defaults or node | `22` | SSH port |
| `identity_file` | defaults or node | your default SSH key | Private key for this node. Created (ed25519, no passphrase) if it does not exist. Used by `ssh`, `scp`, `ssh-copy-id`, the tunnel, and the Hermes profile |
| `local_port` | node | `13000 + position` | Tunnel port on this host. Set it if you reorder or remove nodes, so existing MCP URLs keep their ports |
| `skip_platform_check` | defaults or node | `--skip-platform-check`, else `false` | Writes `PLATFORM_CHECK=false` on that node. CI/validation only |

The file holds **no passwords**, and the script rejects any `password` key. On the first run, `ssh-copy-id` asks for each node user's password once in your terminal, and later runs use the key. The file is parsed with PyYAML (`sudo apt-get install python3-yaml` if missing). Every value is validated before it is used, and node names and local ports must be unique.

Check the file without touching any node:

```bash
~/weld-fleet-setup.sh --list
```

### Run it

Keep the script and `fleet_inventory.py` together, and save your node list as
`~/hosts.yaml` if running from your home directory, then:

```bash
chmod 0755 ~/weld-fleet-setup.sh
~/weld-fleet-setup.sh
```

Without a hosts file, give the IP addresses instead. All nodes then use the same user, port 22, and your default SSH key:

```bash
~/weld-fleet-setup.sh --user deploy 192.168.1.21 192.168.1.22
```

Run it from an interactive terminal: it may ask once per node for the node user's password (to install your SSH key) and for `sudo` (to install packages). It ends with a summary:

```text
==> Summary
NODE        HOST            PROFILE      MCP URL                       STATUS         CONNECT TIME
weld_node1  192.168.1.21    weld-node-1  https://localhost:13001/mcp   connected      8s
weld_node2  192.168.1.22    weld-node-2  https://localhost:13002/mcp   connected      3s
```

Then continue with [section 8](#8-verify-and-operate) to start pipelines and query results.

| Option | Effect |
| --- | --- |
| `--hosts FILE` | Read the nodes from `FILE` instead of `hosts.yaml` next to the script. Cannot be combined with IP addresses |
| `--node NAME`, `--recipe NAME` | Recipe inventories only: select node/recipe assignments; repeatable |
| `--list` | Print the resolved node/deployment plan and exit without changing anything |
| `--user NAME` | SSH user on the nodes (default `deploy`). With a hosts file, used only where the file sets no `user` |
| `--interactive` | Deploy each node in an interactive Hermes chat instead of in parallel. Use this on the first run if approval prompts block the unattended deployment; exit each chat with `/quit` when it finishes |
| `--no-deploy` | Prepare nodes and profiles, and register MCP servers for nodes whose app is already running, without redeploying |
| `--skip-platform-check` | Writes `PLATFORM_CHECK=false` to the node's `.env`. For CI/validation on non-Panther Lake hardware only. With a hosts file, used only where the file sets no `skip_platform_check` |
| `SKILL_SRC=<path>` (environment) | Use a local copy of the `multimodal-deploy` skill instead of fetching it |
| `REPO_URL=<url>`, `REPO_BRANCH=<branch>` (environment) | Repository and branch to clone on the central host and the nodes. Default: `https://github.com/vkb1/manufacturing-ai-suite.git`, branch `migrate/pr-4518`. Existing clones are switched to this branch |

The script is idempotent: run it again with the same hosts file (or the same IPs) to redeploy and refresh the certificates and MCP registrations. Keep the node order the same, or set `name` and `local_port` for each node, because by default the order determines the node names and tunnel ports. Deployment logs are in `~/.hermes/logs/weld-fleet/`.

### Progress logs and stage timing

Progress messages go to stderr with a local timestamp (including timezone), seconds
since this run started, and the node or stage name:

```text
[2026-10-24T16:00:00+0530] [+12s] START: [weld_node1] Prepare node
[2026-10-24T16:00:18+0530] [+30s] DONE: [weld_node1] Prepare node (elapsed=18s)
```

- `START` / `DONE` messages time host checks, skill acquisition, helper and tunnel
  setup, each node's profile and preparation, deployment, and MCP connection.
- Remote preparation reports package checks/installations, Docker group changes,
  and cloning/updating the app, with its own timestamp and elapsed time.
- During unattended deployment, a `WAIT` message every roughly 30 seconds lists
  nodes still deploying and points to their logs. Each node's deployment log also
  includes start/end markers and elapsed time; Hermes output between those markers
  is kept as emitted, without adding timestamps to each line.
- MCP readiness retries report the attempt, HTTP status, and elapsed wait time
  initially and every six unsuccessful attempts. The summary adds `CONNECT TIME`
  per node, and the final message reports total runtime.
- Failed stages report their exit code and elapsed time. As before, a failed
  Hermes deployment does not skip the subsequent MCP readiness check; it now
  produces a warning rather than being silently ignored. MCP connectivity alone
  does not prove the deployment or smoke check succeeded; inspect those warnings
  and the node's deployment log. Recipe mode additionally returns a nonzero
  overall exit code for failed deployments.

No credential values, private key contents, or expanded commands are added to the
progress logs. `--list` still prints only the inventory and performs no setup.
To save the console output as well as each node's deployment log:

```bash
set -o pipefail
umask 077
~/weld-fleet-setup.sh 2>&1 | tee ~/weld-fleet-setup.log
```

### The script

```bash
#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# Prepares nodes, installs deployment skills, deploys apps with their MCP servers,
# and registers each node's MCP server with the Hermes on this host.
set -euo pipefail

SSH_USER=deploy
SKIP_PLATFORM_CHECK=false
DEPLOY=true
INTERACTIVE=false
HOSTS_FILE=
LIST_ONLY=false
SELECTORS=()

REPO_URL=${REPO_URL:-https://github.com/vkb1/manufacturing-ai-suite.git}
REPO_BRANCH=${REPO_BRANCH:-migrate/pr-4518}
REMOTE_ROOT=${REMOTE_ROOT:-manufacturing-ai-suite}
APP_SUBDIR=${APP_SUBDIR:-industrial-edge-insights-multimodal}
APP_REL="$REMOTE_ROOT/$APP_SUBDIR"
REMOTE_PORT=${REMOTE_PORT:-3000}
BASE_PORT=13000
USER_KEYS=(INFLUXDB_USERNAME VISUALIZER_GRAFANA_USER MTX_WEBRTCICESERVERS2_0_USERNAME S3_STORAGE_USERNAME SEAWEEDFS_WEB_AUTH_USER MCP_USERNAME)
PASS_KEYS=(INFLUXDB_PASSWORD VISUALIZER_GRAFANA_PASSWORD MTX_WEBRTCICESERVERS2_0_PASSWORD S3_STORAGE_PASSWORD SEAWEEDFS_WEB_AUTH_PASSWORD MCP_PASSWORD)
MCP_TOOLS='["describe","list_insights_data","explain","run_agent","get_run_results","start_pipeline","stop_pipeline"]'
SKILL_NAME=${SKILL_NAME:-multimodal-deploy}
SKILL_PATH=${SKILL_PATH:-$APP_SUBDIR/.github/skills/$SKILL_NAME}
SKILL_REPO_URL=${SKILL_REPO_URL:-$REPO_URL}
SKILL_REPO_REF=${SKILL_REPO_REF:-$REPO_BRANCH}
MCP_SCHEME=${MCP_SCHEME:-https}
MCP_PATH=${MCP_PATH:-/mcp}
MCP_CERT_CONTAINER=${MCP_CERT_CONTAINER-nginx_proxy}
MCP_CERT_PATH=${MCP_CERT_PATH:-/opt/nginx/certs/cert.pem}
MCP_AUTH_TYPE=${MCP_AUTH_TYPE:-basic}
MCP_USER_KEY=${MCP_USER_KEY:-MCP_USERNAME}
MCP_PASS_KEY=${MCP_PASS_KEY:-MCP_PASSWORD}
MCP_TOKEN_KEY=${MCP_TOKEN_KEY:-MCP_TOKEN}
if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
  mapfile -t USER_KEYS < <(python3 -c 'import json,os; print("\n".join(json.loads(os.environ["USER_KEYS_JSON"])))')
  mapfile -t PASS_KEYS < <(python3 -c 'import json,os; print("\n".join(json.loads(os.environ["PASS_KEYS_JSON"])))')
  # Empty lists must not create a single empty variable name.
  [[ -n ${USER_KEYS[0]:-} ]] || USER_KEYS=()
  [[ -n ${PASS_KEYS[0]:-} ]] || PASS_KEYS=()
  MCP_TOOLS=${MCP_TOOLS_JSON:-'[]'}
fi
DEPLOY_PROMPT=${DEPLOY_PROMPT:-"In ~/$APP_REL, deploy the agentic variant with the MCP server (make up_agentic MCP=true), then run the smoke check. Do not edit .env; if a required credential is missing, stop and name it. Do not start or stop pipelines."}
SMART_POLICY=${SMART_POLICY:-"APPROVE make build, make up_agentic, make down and make status (with or without MCP=true) and .github/skills/multimodal-deploy/scripts/smoke-check.sh when run from ~/$APP_REL. ESCALATE anything that edits .env, uses sudo, or touches paths outside that directory."}

RUN_STARTED=$SECONDS
log() { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] [+%ss] %s\n' -1 "$((SECONDS - RUN_STARTED))" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
stage_finished() {
  if (( $1 == 0 )); then
    log "DONE: $STAGE_LABEL (elapsed=$((SECONDS - STAGE_STARTED))s)"
  else
    log "ERROR: $STAGE_LABEL (exit=$1, elapsed=$((SECONDS - STAGE_STARTED))s)"
  fi
}
run_stage() (
  STAGE_LABEL=$1 STAGE_STARTED=$SECONDS
  shift
  trap 'stage_finished "$?"' EXIT
  log "START: $STAGE_LABEL"
  "$@"
)
usage() {
  cat >&2 <<EOF
usage: $0 [--hosts FILE] [--list] [--user NAME] [--interactive] [--no-deploy] [--skip-platform-check]
       $0 [--list] [--user NAME] [--interactive] [--no-deploy] [--skip-platform-check] <node-ip> [<node-ip> ...]
Without node IPs, nodes are read from FILE (default: hosts.yaml next to this script).
--list prints the resolved nodes and exits without changing anything.
--node NAME and --recipe NAME select deployments from a recipe inventory (repeatable).
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --hosts) [[ $# -ge 2 ]] || usage; HOSTS_FILE=$2; shift 2 ;;
    --list) LIST_ONLY=true; shift ;;
    --node|--recipe) [[ $# -ge 2 ]] || usage; SELECTORS+=("$1" "$2"); shift 2 ;;
    --user) [[ $# -ge 2 ]] || usage; SSH_USER=$2; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --no-deploy) DEPLOY=false; shift ;;
    --skip-platform-check) SKIP_PLATFORM_CHECK=true; shift ;;
    -h|--help|-*) usage ;;
    *) break ;;
  esac
done
if [[ $# == 0 && ${FLEET_RECIPE_MODE:-} != 1 ]]; then
  HOSTS_FILE=${HOSTS_FILE:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hosts.yaml"}
  command -v python3 >/dev/null || die "python3 is required for YAML inventories"
  python3 -c 'import yaml' 2>/dev/null || die "PyYAML is required (install python3-yaml)"
  inventory_kind=$(python3 - "$HOSTS_FILE" <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as stream:
        doc = yaml.safe_load(stream)
    print("recipes" if isinstance(doc, dict) and "recipes" in doc else "legacy")
except (OSError, yaml.YAMLError):
    sys.exit("ERROR: cannot read inventory; check the file path and YAML syntax")
PY
  ) || exit 2
  if [[ $inventory_kind == recipes ]]; then
    inventory_args=(--hosts "$HOSTS_FILE" --script "${BASH_SOURCE[0]}" --user "$SSH_USER" "${SELECTORS[@]}")
    $LIST_ONLY && inventory_args+=(--list)
    $INTERACTIVE && inventory_args+=(--interactive)
    $DEPLOY || inventory_args+=(--no-deploy)
    $SKIP_PLATFORM_CHECK && inventory_args+=(--skip-platform-check)
    exec python3 "$(dirname "${BASH_SOURCE[0]}")/fleet_inventory.py" "${inventory_args[@]}"
  fi
fi
(( ${#SELECTORS[@]} == 0 )) || die "--node/--recipe require a recipe inventory"
[[ $# -ge 1 && -n $HOSTS_FILE ]] && die "give either --hosts or node IPs, not both"
[[ $SSH_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid --user: $SSH_USER"
[[ $REPO_URL =~ ^https://[A-Za-z0-9./_-]+$ ]] || die "invalid REPO_URL: $REPO_URL"
[[ $REPO_BRANCH =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid REPO_BRANCH: $REPO_BRANCH"

# Per-node settings by position (0-based). Node N (1-based) defaults to name weld_nodeN and local port BASE_PORT+N.
NAME=() HOST=() NUSER=() SSH_PORT=() KEY=() LPORT=() SKIP=()

# Prints one tab-separated line per node: name host user port identity_file local_port skip_platform_check.
read_hosts_file() {
  command -v python3 >/dev/null || die "python3 is needed to read $1"
  python3 -c 'import yaml' 2>/dev/null || die "PyYAML is needed to read $1 (sudo apt-get install python3-yaml)"
  python3 - "$1" "$SSH_USER" "$SKIP_PLATFORM_CHECK" <<'PY'
import sys, yaml

path, cli_user, cli_skip = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
NODE_KEYS = {"name", "host", "user", "port", "identity_file", "local_port", "skip_platform_check"}
DEFAULT_KEYS = {"user", "port", "identity_file", "skip_platform_check"}

def fail(msg):
    sys.exit(f"ERROR: {path}: {msg}")

try:
    with open(path) as f:
        doc = yaml.safe_load(f) or {}
except (OSError, yaml.YAMLError) as e:
    fail(f"cannot read: {e}")
if not isinstance(doc, dict) or set(doc) - {"defaults", "nodes"}:
    fail("the top level may contain only 'defaults' and 'nodes'")
defaults = doc.get("defaults") or {}
nodes = doc.get("nodes") or []
if not isinstance(defaults, dict):
    fail("'defaults' must be a mapping")
if not isinstance(nodes, list) or not nodes:
    fail("'nodes' must be a non-empty list")
for d in [defaults, *nodes]:
    if isinstance(d, dict) and any("pass" in str(k).lower() for k in d):
        fail("passwords are not supported; use key-based SSH (identity_file)")
if set(defaults) - DEFAULT_KEYS:
    fail(f"'defaults' may contain only {sorted(DEFAULT_KEYS)}")

for i, node in enumerate(nodes, 1):
    if not isinstance(node, dict):
        fail(f"node {i} must be a mapping")
    if set(node) - NODE_KEYS:
        fail(f"node {i}: unknown keys {sorted(set(node) - NODE_KEYS)}")
    if "host" not in node:
        fail(f"node {i}: 'host' is required")
    v = {"name": f"weld_node{i}", "user": cli_user, "port": 22, "identity_file": "", "local_port": 0,
         "skip_platform_check": cli_skip, **defaults, **node}
    if not isinstance(v["skip_platform_check"], bool):
        fail(f"node {i}: skip_platform_check must be true or false")
    for k in ("port", "local_port"):
        if not isinstance(v[k], int) or isinstance(v[k], bool):
            fail(f"node {i}: {k} must be a number")
    fields = [str(x) for x in (v["name"], v["host"], v["user"], v["port"], v["identity_file"] or "-",
                               v["local_port"], str(v["skip_platform_check"]).lower())]
    if any(not x or any(c.isspace() for c in x) for x in fields):
        fail(f"node {i}: values must be non-empty and contain no whitespace")
    print("\t".join(fields))
PY
}

valid_host() {
  local h=$1 o
  if [[ $h =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
    return 0
  fi
  [[ ${#h} -le 253 && $h =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$ ]]
}

if [[ $# -ge 1 ]]; then
  for ip in "$@"; do
    NAME+=("weld_node$((${#NAME[@]} + 1))") HOST+=("$ip") NUSER+=("$SSH_USER") SSH_PORT+=(22) KEY+=("")
    LPORT+=(0) SKIP+=("$SKIP_PLATFORM_CHECK")
  done
else
  HOSTS_FILE=${HOSTS_FILE:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hosts.yaml"}
  [[ -f $HOSTS_FILE ]] || { echo "ERROR: no node IPs given and $HOSTS_FILE not found" >&2; usage; }
  hosts_tsv=$(read_hosts_file "$HOSTS_FILE") || exit 1
  while IFS=$'\t' read -r n h u p k lp sk; do
    [[ $k == - ]] && k=""
    NAME+=("$n") HOST+=("$h") NUSER+=("$u") SSH_PORT+=("$p") KEY+=("$k") LPORT+=("$lp") SKIP+=("$sk")
  done <<<"$hosts_tsv"
fi

declare -A seen_name seen_port
for i in "${!NAME[@]}"; do
  n=${NAME[i]}
  [[ $n =~ ^[a-z][a-z0-9_]{0,31}$ ]] || die "invalid node name: $n (lowercase letters, digits, _)"
  valid_host "${HOST[i]}" || die "[$n] not an IPv4 address or hostname: ${HOST[i]}"
  [[ ${NUSER[i]} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "[$n] invalid user: ${NUSER[i]}"
  if ! [[ ${SSH_PORT[i]} =~ ^[0-9]{1,5}$ ]] || (( SSH_PORT[i] < 1 || SSH_PORT[i] > 65535 )); then
    die "[$n] invalid port: ${SSH_PORT[i]}"
  fi
  [[ ${LPORT[i]} == 0 ]] && LPORT[i]=$((BASE_PORT + i + 1))
  if ! [[ ${LPORT[i]} =~ ^[0-9]{4,5}$ ]] || (( LPORT[i] < 1024 || LPORT[i] > 65535 )); then
    die "[$n] invalid local_port: ${LPORT[i]}"
  fi
  if [[ -n ${KEY[i]} ]]; then
    # shellcheck disable=SC2088  # matching a literal "~/" from the hosts file
    [[ ${KEY[i]} == "~/"* ]] && KEY[i]="$HOME/${KEY[i]:2}"
    [[ ${KEY[i]} =~ ^/[A-Za-z0-9._/-]+$ && ${KEY[i]} != *..* ]] \
      || die "[$n] identity_file must be an absolute or ~/ path without spaces: ${KEY[i]}"
  fi
  [[ ${SKIP[i]} == true || ${SKIP[i]} == false ]] || die "[$n] invalid skip_platform_check: ${SKIP[i]}"
  [[ -z ${seen_name[$n]:-} ]] || die "duplicate node name: $n"
  [[ -z ${seen_port[${LPORT[i]}]:-} ]] || die "[$n] local_port ${LPORT[i]} is already used by ${seen_port[${LPORT[i]}]}"
  seen_name[$n]=1 seen_port[${LPORT[i]}]=$n
done

# Hermes profile per node: weld_nodeN -> weld-node-N (as in the manual sections); other names: _ -> -.
profile_of() {
  if [[ $1 =~ ^weld_node([0-9]+)$ ]]; then printf 'weld-node-%s' "${BASH_REMATCH[1]}"; else printf '%s' "${1//_/-}"; fi
}

# ssh and scp with the node's port and key; the first argument is the node index.
node_opts() {
  local i=$1 port_flag=$2
  NODE_OPTS=("$port_flag" "${SSH_PORT[i]}")
  if [[ -n ${KEY[i]} ]]; then NODE_OPTS+=(-i "${KEY[i]}" -o IdentitiesOnly=yes); fi
}
# shellcheck disable=SC2029  # remote commands are fixed strings with validated arguments
nssh() { node_opts "$1" -p; shift; ssh "${NODE_OPTS[@]}" "$@"; }
nscp() { node_opts "$1" -P; shift; scp -q "${NODE_OPTS[@]}" "$@"; }

if $LIST_ONLY; then
  printf '%-11s %-15s %-10s %-5s %-12s %-6s %-14s %s\n' NODE HOST USER PORT PROFILE LOCAL SKIP_PLATFORM IDENTITY_FILE
  for i in "${!NAME[@]}"; do
    printf '%-11s %-15s %-10s %-5s %-12s %-6s %-14s %s\n' "${NAME[i]}" "${HOST[i]}" "${NUSER[i]}" "${SSH_PORT[i]}" \
      "$(profile_of "${NAME[i]}")" "${LPORT[i]}" "${SKIP[i]}" "${KEY[i]:-(ssh default)}"
  done
  exit 0
fi

finish() {
  local result=$?
  if [[ -n ${LOCAL_TMP:-} ]]; then rm -rf "$LOCAL_TMP"; fi
  if (( result == 0 )); then
    log "DONE: Fleet setup (nodes=${#NAME[@]}, total=$((SECONDS - RUN_STARTED))s)"
  else
    log "ERROR: Fleet setup (exit=$result, total=$((SECONDS - RUN_STARTED))s); see the last stage above"
  fi
}
trap finish EXIT
log "Inventory validated: ${#NAME[@]} node(s); deploy=$DEPLOY; interactive=$INTERACTIVE"

rand_user() { printf 'weld%s' "$(openssl rand -base64 48 | tr -dc 'a-z' | cut -c1-8)"; }
rand_pass() { printf '%sa7' "$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-22)"; }

set_central_env() {
  local f="$HOME/.hermes/.env" tmp
  tmp=$(mktemp "$f.XXXXXX")
  { grep -v "^$1=" "$f" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
  mv "$tmp" "$f"
}

write_helpers() {
  cat > "$LOCAL_TMP/node-prepare.sh" <<'REMOTE'
set -euo pipefail
repo_url=$1 branch=$2 root=$HOME/$3 app_subdir=$4
log() { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] [remote +%ss] %s\n' -1 "$SECONDS" "$*" >&2; }
trap 'result=$?; log "Node preparation finished (exit=$result, elapsed=${SECONDS}s)"' EXIT
log "Checking packages and Docker Compose"
need=()
for c in make curl git; do command -v "$c" >/dev/null || need+=("$c"); done
command -v docker >/dev/null || need+=(docker.io)
docker compose version >/dev/null 2>&1 || need+=(docker-compose-v2)
if (( ${#need[@]} )); then
  command -v apt-get >/dev/null || { echo "Install these on $(hostname) first: ${need[*]}" >&2; exit 1; }
  log "Installing missing packages: ${need[*]} (sudo may prompt)"
  sudo apt-get update -q
  sudo apt-get install -y -q "${need[@]}"
fi
log "Package checks complete; checking Docker group membership"
if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then
  log "Adding deployment user to Docker group (sudo may prompt)"
  sudo usermod -aG docker "$USER"
fi
if [[ ${5:-node_clone} == central_copy ]]; then
  bundle=$6 digest=$7 commit=$8
  log "Verifying transferred Git bundle"
  printf '%s  %s\n' "$digest" "$bundle" | sha256sum --check --status
  git bundle list-heads "$bundle" >/dev/null
  if [[ -d $root/.git ]]; then
    log "Updating checkout from central bundle (no upstream fetch)"
    git -C "$root" fetch -q "$bundle" refs/heads/fleet-source
    [[ $(git -C "$root" rev-parse FETCH_HEAD) == "$commit" ]]
    git -C "$root" checkout -q --no-overwrite-ignore -B "$branch" FETCH_HEAD
  else
    [[ ! -e $root ]] || { echo "Existing non-Git path blocks source delivery" >&2; exit 1; }
    log "Creating checkout from central bundle (no upstream clone)"
    git clone -q --sparse --branch fleet-source "$bundle" "$root"
    if [[ $app_subdir == . ]]; then
      git -C "$root" sparse-checkout disable
    else
      git -C "$root" sparse-checkout set "$app_subdir"
    fi
    git -C "$root" checkout -q -B "$branch" "$commit"
    git -C "$root" remote set-url origin "$repo_url"
  fi
  git -C "$root" bundle verify "$bundle"
  [[ $(git -C "$root" rev-parse HEAD) == "$commit" ]]
  log "Central source installed at commit $commit"
elif [[ -d $root/.git ]]; then
  log "Fetching app branch and updating existing checkout"
  git -C "$root" fetch -q "$repo_url" "$branch"
  git -C "$root" checkout -q -B "$branch" FETCH_HEAD \
    || { echo "Local changes in $root block switching to $branch (usually .env); commit or stash them and rerun" >&2; exit 1; }
else
  log "Cloning app branch (this may take several minutes)"
  git clone -q --filter=blob:none --sparse --branch "$branch" "$repo_url" "$root"
  git -C "$root" sparse-checkout set "$app_subdir"
fi
log "App checkout ready"
REMOTE

  cat > "$LOCAL_TMP/env-merge.sh" <<'REMOTE'
set -euo pipefail
env_file=$1 updates=$2
trap 'rm -f "$updates"' EXIT
touch "$env_file"
while read -r mode key val; do
  cur=$(sed -n "s/^${key}=//p" "$env_file" | tail -n 1)
  [[ $mode == fill && -n $cur ]] && continue
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$env_file"
  fi
done < "$updates"
chmod 600 "$env_file"
REMOTE
}

write_tunnel_unit() {
  install -d "$HOME/.config/systemd/user" "$HOME/.config/weld-tunnels"
  cat > "$HOME/.config/systemd/user/weld-tunnel@.service" <<'UNIT'
[Unit]
Description=SSH tunnel to multimodal nginx (%i)
After=network-online.target

[Service]
EnvironmentFile=%h/.config/weld-tunnels/%i.env
ExecStart=/usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 $SSH_OPTS -L ${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} ${NODE}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  loginctl enable-linger "$USER" || log "WARN: could not enable linger; tunnels stop when you log out"
}

setup_profile() {
  local i=$1 ip=${HOST[$1]} p profiles dst
  p=$(profile_of "${NAME[i]}")
  log "[$p] Hermes profile for $ip"
  profiles=$(hermes profile list 2>/dev/null || true)
  if ! grep -qw -- "$p" <<<"$profiles"; then
    log "[${NAME[i]}] Creating Hermes profile"
    hermes profile create "$p" --clone --description "Runs $SKILL_NAME on $ip over SSH"
    hermes -p "$p" config unset mcp_servers >/dev/null 2>&1 || true
  fi
  log "[${NAME[i]}] Configuring SSH backend, timeout, approval policy, and deploy skill"
  hermes -p "$p" config set terminal.backend ssh
  hermes -p "$p" config set TERMINAL_SSH_HOST "$ip"
  hermes -p "$p" config set TERMINAL_SSH_USER "${NUSER[i]}"
  hermes -p "$p" config set TERMINAL_SSH_PORT "${SSH_PORT[i]}"
  if [[ -n ${KEY[i]} ]]; then
    hermes -p "$p" config set TERMINAL_SSH_KEY "${KEY[i]}"
  else
    hermes -p "$p" config unset TERMINAL_SSH_KEY >/dev/null 2>&1 || true
  fi
  hermes -p "$p" config set terminal.timeout 3600
  hermes -p "$p" config set approvals.smart_policy "$SMART_POLICY"
  dst="$HOME/.hermes/profiles/$p/skills/devops"
  install -d "$dst"
  [[ $SKILL_NAME =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || die "invalid skill name"
  rm -rf "${dst:?}/${SKILL_NAME:?}"
  cp -r "$SKILL_SRC" "$dst/$SKILL_NAME"
}

prepare_node() {
  local i=$1 ip=${HOST[$1]} name=${NAME[$1]} target="${NUSER[$1]}@${HOST[$1]}" rtmp upd creds mcp_user mcp_pass
  local copy_id=(-p "${SSH_PORT[$1]}" -o StrictHostKeyChecking=accept-new)
  if [[ -n ${KEY[i]} ]]; then copy_id+=(-i "${KEY[i]}.pub"); fi
  log "[$name] Checking key-based SSH connectivity"
  if ! nssh "$i" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$target" true 2>/dev/null; then
    log "[$name] SSH check failed; installing public key (enter the node password in the terminal)"
    run_stage "[$name] Install SSH public key" ssh-copy-id "${copy_id[@]}" "$target"
  fi
  log "[$name] SSH ready; creating remote workspace and uploading helpers"

  rtmp=$(nssh "$i" "$target" mktemp -d)
  [[ $rtmp =~ ^/[A-Za-z0-9._/-]+$ ]] || die "[$name] unexpected remote temp dir"
  nscp "$i" "$LOCAL_TMP/node-prepare.sh" "$LOCAL_TMP/env-merge.sh" "$target:$rtmp/"
  local source_args=()
  if [[ ${SOURCE_DELIVERY:-node_clone} == central_copy ]]; then
    log "[$name] Transferring centrally prepared app source (commit=$SOURCE_COMMIT)"
    nscp "$i" "$SOURCE_BUNDLE" "$target:$rtmp/source.bundle"
    source_args=(central_copy "$rtmp/source.bundle" "$SOURCE_SHA256" "$SOURCE_COMMIT")
  fi
  run_stage "[$name] Packages, Docker group, and app checkout" \
    nssh "$i" -t "$target" bash "$rtmp/node-prepare.sh" "$REPO_URL" "$REPO_BRANCH" "$REMOTE_ROOT" "$APP_SUBDIR" "${source_args[@]}"
  log "[$name] Verifying Docker access in a new SSH session"
  nssh "$i" "$target" docker info >/dev/null 2>&1 || die "[$name] ${NUSER[i]} cannot use Docker on $ip"

  log "[$name] Preparing missing app credentials (values will not be logged)"
  upd="$LOCAL_TMP/$name.updates"
  {
    for k in "${USER_KEYS[@]}"; do printf 'fill %s %s\n' "$k" "$(rand_user)"; done
    for k in "${PASS_KEYS[@]}"; do printf 'fill %s %s\n' "$k" "$(rand_pass)"; done
    if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
      python3 - <<'PY'
import json, os
for key, value in json.loads(os.environ["ENV_UPDATES_JSON"]).items():
    print(f"set {key} {value}")
PY
    else
      printf 'set HOST_IP 127.0.0.1\n'
    fi
    if [[ ${SKIP[i]} == true ]]; then printf 'set PLATFORM_CHECK false\n'; fi
  } > "$upd"
  nscp "$i" "$upd" "$target:$rtmp/updates"
  rm -f "$upd"
  run_stage "[$name] Apply app environment updates" \
    nssh "$i" "$target" bash "$rtmp/env-merge.sh" "$APP_REL/.env" "$rtmp/updates"
  log "[$name] Removing remote temporary files"
  nssh "$i" "$target" rm -rf "$rtmp"

  if [[ $MCP_AUTH_TYPE == basic ]]; then
    log "[$name] Saving MCP authentication on central host (values will not be logged)"
    creds=$(nssh "$i" "$target" grep -E "'^($MCP_USER_KEY|$MCP_PASS_KEY)='" "$APP_REL/.env")
    mcp_user=$(sed -n "s/^$MCP_USER_KEY=//p" <<<"$creds" | tail -n 1)
    mcp_pass=$(sed -n "s/^$MCP_PASS_KEY=//p" <<<"$creds" | tail -n 1)
    [[ -n $mcp_user && -n $mcp_pass ]] || die "[$name] MCP credentials missing in the node's .env"
    set_central_env "${name^^}_MCP_BASIC" "$(printf '%s:%s' "$mcp_user" "$mcp_pass" | base64 -w0)"
  elif [[ $MCP_AUTH_TYPE == bearer ]]; then
    log "[$name] Saving MCP token on central host (value will not be logged)"
    creds=$(nssh "$i" "$target" grep -E "'^$MCP_TOKEN_KEY='" "$APP_REL/.env")
    mcp_pass=$(sed -n "s/^$MCP_TOKEN_KEY=//p" <<<"$creds" | tail -n 1)
    [[ -n $mcp_pass ]] || die "[$name] MCP token missing in the node's .env"
    [[ $mcp_pass =~ ^[A-Za-z0-9._~+/-]+=*$ ]] || die "[$name] MCP bearer token has an unsupported format"
    set_central_env "${name^^}_MCP_TOKEN" "$mcp_pass"
  fi
}

deploy_node() {
  local p=$1 file=$2 started=$SECONDS result=0
  log "START: Deployment and smoke check" > "$file" 2>&1
  if hermes -p "$p" chat -s "$SKILL_NAME" --oneshot -q "$DEPLOY_PROMPT" >> "$file" 2>&1; then
    log "DONE: Deployment and smoke check (elapsed=$((SECONDS - started))s)" >> "$file" 2>&1
  else
    result=$?
    log "ERROR: Deployment and smoke check (exit=$result, elapsed=$((SECONDS - started))s)" >> "$file" 2>&1
  fi
  return "$result"
}

deploy_all() {
  local i n p pid result active next_report=$((SECONDS + 30))
  local log_dir="$HOME/.hermes/logs/weld-fleet" pids=() nodes=()
  install -d "$log_dir"
  for i in "${!NAME[@]}"; do
    n=${NAME[i]} p=$(profile_of "${NAME[i]}")
    if $INTERACTIVE; then
      log "[$p] Interactive deployment; enter /quit when it finishes"
      if run_stage "[$n] Interactive deployment" \
        hermes -p "$p" chat -s "$SKILL_NAME" -q "$DEPLOY_PROMPT"; then
        log "[$n] Hermes chat completed; MCP readiness will be checked separately"
      else
        result=$?
        log "WARN: [$n] Hermes chat exited with $result; continuing to MCP readiness check"
        printf '%s\n' "$result" > "$LOCAL_TMP/$n.deploy-failed"
      fi
    else
      log "[$p] Deploying skill $SKILL_NAME in the background (log: $log_dir/$n.deploy.log)"
      run_stage "[$n] Deployment (log: $log_dir/$n.deploy.log)" deploy_node "$p" "$log_dir/$n.deploy.log" &
      pids+=("$!")
      nodes+=("$n")
    fi
  done
  while :; do
    active=()
    for i in "${!pids[@]}"; do
      if kill -0 "${pids[i]}" 2>/dev/null; then active+=("${nodes[i]}"); fi
    done
    (( ${#active[@]} )) || break
    if (( SECONDS >= next_report )); then
      log "WAIT: Deployment still running on ${active[*]}; follow $log_dir/<node>.deploy.log"
      next_report=$((SECONDS + 30))
    fi
    sleep 5
  done
  # The MCP check in connect_node decides success, not the agent's exit code.
  for i in "${!pids[@]}"; do
    pid=${pids[i]}
    if wait "$pid"; then
      log "[${nodes[i]}] Hermes deployment completed; MCP readiness will be checked separately"
    else
      result=$?
      log "WARN: [${nodes[i]}] Deployment exited with $result; see $log_dir/${nodes[i]}.deploy.log; continuing to MCP readiness check"
      printf '%s\n' "$result" > "$LOCAL_TMP/${nodes[i]}.deploy-failed"
    fi
  done
}

connect_node() {
  local i=$1 ip=${HOST[$1]} name=${NAME[$1]} target="${NUSER[$1]}@${HOST[$1]}" port=${LPORT[$1]}
  local cert="$HOME/.hermes/certs/${NAME[$1]}.pem" url="$MCP_SCHEME://localhost:${LPORT[$1]}$MCP_PATH" code=000
  local attempt ready_started tls_args=()
  node_opts "$i" -p
  # systemd splits $SSH_OPTS on spaces; all values were validated to contain none.
  printf 'LOCAL_PORT=%s\nREMOTE_PORT=%s\nNODE=%s\nSSH_OPTS=%s\n' "$port" "$REMOTE_PORT" "$target" "${NODE_OPTS[*]}" \
    > "$HOME/.config/weld-tunnels/$name.env"
  log "[$name] Starting SSH tunnel on local port $port"
  systemctl --user enable -q "weld-tunnel@$name"
  systemctl --user restart "weld-tunnel@$name"

  # Refresh the pin over authenticated SSH, because app certificates may change on redeploy.
  install -d -m 0700 "$HOME/.hermes/certs"
  if [[ $MCP_SCHEME == https ]]; then
    log "[$name] Fetching and validating current MCP certificate over SSH"
    if [[ -n $MCP_CERT_CONTAINER ]]; then
      nssh "$i" "$target" docker exec "$MCP_CERT_CONTAINER" cat "$MCP_CERT_PATH" > "$cert.tmp" \
        || die "[$name] cannot fetch MCP certificate"
    else
      nssh "$i" "$target" cat "$MCP_CERT_PATH" > "$cert.tmp" \
        || die "[$name] cannot fetch MCP certificate"
    fi
    openssl x509 -in "$cert.tmp" -noout
    mv "$cert.tmp" "$cert"
    tls_args=(--cacert "$cert")
  fi

  ready_started=$SECONDS
  log "[$name] Waiting for MCP tools/list readiness (up to 60 attempts)"
  for attempt in {1..60}; do
    # Authenticated endpoints are verified by Hermes below; do not put secrets in curl's argv.
    code=$(curl -s --connect-timeout 5 --max-time 15 "${tls_args[@]}" -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || true)
    [[ $code == 200 || ( $MCP_AUTH_TYPE != none && $code == 401 ) ]] && break
    if (( attempt == 1 || attempt % 6 == 0 )); then
      log "WAIT: [$name] MCP not ready (attempt=$attempt/60, HTTP=$code, elapsed=$((SECONDS - ready_started))s)"
    fi
    sleep 5
  done
  [[ $code == 200 || ( $MCP_AUTH_TYPE != none && $code == 401 ) ]] || die "[$name] $url not ready (HTTP $code)"
  log "[$name] MCP endpoint responding (HTTP=$code, attempt=$attempt/60, elapsed=$((SECONDS - ready_started))s); verifying with Hermes next"

  log "[$name] Registering MCP URL, pinned certificate, credential reference, and tool allow-list"
  hermes config set "mcp_servers.$name.url" "$url"
  if [[ $MCP_SCHEME == https ]]; then
    hermes config set "mcp_servers.$name.ssl_verify" "$cert"
  else
    hermes config set "mcp_servers.$name.ssl_verify" true
  fi
  case $MCP_AUTH_TYPE in
    basic) hermes config set "mcp_servers.$name.headers.Authorization" "Basic \${${name^^}_MCP_BASIC}" ;;
    bearer) hermes config set "mcp_servers.$name.headers.Authorization" "Bearer \${${name^^}_MCP_TOKEN}" ;;
    none) hermes config set "mcp_servers.$name.headers" '{}' ;;
  esac
  hermes config set "mcp_servers.$name.tools.include" "$MCP_TOOLS"
  run_stage "[$name] Hermes MCP verification" hermes mcp test "$name" >/dev/null
}

ensure_user_systemd() {
  if systemctl --user show-environment >/dev/null 2>&1; then
    return 0
  fi
  local runtime_dir="/run/user/$(id -u)"
  if test -S "$runtime_dir/bus" && test -O "$runtime_dir" && test -O "$runtime_dir/bus"; then
    export XDG_RUNTIME_DIR="$runtime_dir"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
    if systemctl --user show-environment >/dev/null; then
      log "Recovered systemd user-session environment from $runtime_dir"
      return 0
    fi
  elif ! systemctl --user show-environment >/dev/null; then
    log "No existing user-owned systemd bus socket at $runtime_dir/bus"
  fi
  die "systemd user services are unavailable for UID $(id -u). Run from a normal login/SSH session as the central-host user, not via sudo or a container. If needed, ask an administrator to run loginctl enable-linger for that user, then log in again."
}

stage_started=$SECONDS
log "START: Central host prerequisites and SSH keys"
for c in hermes ssh scp ssh-copy-id ssh-keygen curl openssl git base64 systemctl loginctl; do
  command -v "$c" >/dev/null || die "missing on this host: $c"
done
ensure_user_systemd
install -d -m 0700 "$HOME/.hermes" "$HOME/.ssh"
if ! compgen -G "$HOME/.ssh/id_*.pub" >/dev/null; then
  log "Creating default SSH key (private key contents will not be logged)"
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
fi
for i in "${!KEY[@]}"; do
  k=${KEY[i]}
  [[ -n $k ]] || continue
  if [[ ! -e $k ]]; then
    log "[${NAME[i]}] Creating configured SSH key (private key contents will not be logged)"
    install -d -m 0700 "$(dirname "$k")"
    ssh-keygen -q -t ed25519 -N '' -C "weld-fleet@$(hostname)" -f "$k"
  fi
  [[ -f $k.pub ]] || die "[${NAME[i]}] public key $k.pub not found"
done
log "DONE: Central host prerequisites and SSH keys (elapsed=$((SECONDS - stage_started))s)"

stage_started=$SECONDS
log "START: Acquire $SKILL_NAME skill"
if [[ -z ${SKILL_SRC:-} ]]; then
  cache="$HOME/.cache/weld-fleet/${REMOTE_ROOT}-${SKILL_NAME}"
  if [[ -d $cache/.git ]]; then
    log "Updating cached skill checkout"
    git -C "$cache" fetch -q "$SKILL_REPO_URL" "$SKILL_REPO_REF"
    git -C "$cache" checkout -q -f -B "$SKILL_REPO_REF" FETCH_HEAD
  else
    log "Cloning skill source (this may take several minutes)"
    git clone -q --filter=blob:none --sparse --branch "$SKILL_REPO_REF" "$SKILL_REPO_URL" "$cache"
  fi
  git -C "$cache" sparse-checkout set "$SKILL_PATH"
  SKILL_SRC="$cache/$SKILL_PATH"
else
  log "Using supplied local skill directory"
fi
[[ -f $SKILL_SRC/SKILL.md ]] || die "$SKILL_NAME skill not found at $SKILL_SRC"
if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
  python3 - "$SKILL_SRC/SKILL.md" "$SKILL_NAME" <<'PY'
import sys, yaml
from pathlib import Path
try:
    content = Path(sys.argv[1]).read_text()
    parts = content.split("---", 2)
    metadata = yaml.safe_load(parts[1]) if content.startswith("---\n") and len(parts) == 3 else None
    if not isinstance(metadata, dict) or metadata.get("name") != sys.argv[2]:
        sys.exit("ERROR: SKILL.md frontmatter name must match the configured skill name")
except (OSError, yaml.YAMLError):
    sys.exit("ERROR: cannot read skill metadata")
PY
fi
log "DONE: Acquire $SKILL_NAME skill (elapsed=$((SECONDS - stage_started))s)"

LOCAL_TMP=$(mktemp -d)
run_stage "Write remote helper scripts" write_helpers
run_stage "Install SSH tunnel service template" write_tunnel_unit

# Profiles first, so they don't clone MCP credentials stored for other nodes.
for i in "${!NAME[@]}"; do run_stage "[${NAME[i]}] Configure Hermes profile" setup_profile "$i"; done
for i in "${!NAME[@]}"; do run_stage "[${NAME[i]}] Prepare node" prepare_node "$i"; done
if $DEPLOY; then
  run_stage "Deploy apps across fleet" deploy_all
else
  log "SKIP: App deployment (--no-deploy); checking existing MCP servers"
fi

declare -A status connection_time
rc=0
for i in "${!NAME[@]}"; do
  log "[${NAME[i]}] Connecting the MCP server"
  # Run in a background job so a failure on one node doesn't stop the others.
  stage_started=$SECONDS
  run_stage "[${NAME[i]}] Connect MCP server" connect_node "$i" &
  if wait "$!"; then status[$i]=connected; else status[$i]="not connected"; rc=1; fi
  if [[ ${FLEET_RECIPE_MODE:-} == 1 && -f $LOCAL_TMP/${NAME[i]}.deploy-failed ]]; then
    status[$i]="deploy failed"
    rc=1
  fi
  connection_time[$i]=$((SECONDS - stage_started))
done

log "Summary"
printf '%-11s %-15s %-12s %-29s %-14s %s\n' NODE HOST PROFILE "MCP URL" STATUS "CONNECT TIME"
for i in "${!NAME[@]}"; do
  printf '%-11s %-15s %-12s %-29s %-14s %ss\n' "${NAME[i]}" "${HOST[i]}" "$(profile_of "${NAME[i]}")" \
    "$MCP_SCHEME://localhost:${LPORT[i]}$MCP_PATH" "${status[$i]}" "${connection_time[$i]}"
done
[[ $rc -eq 0 ]] || log "Deployment logs: $HOME/.hermes/logs/weld-fleet/"
exit "$rc"
```

---

## 3. Prepare the nodes

Do this once per node, logged in over SSH. Credentials are entered on the node directly, never through a Hermes chat.

1. **Clone the app** (a sparse clone is enough):

   ```bash
   git clone --filter=blob:none --sparse --branch migrate/pr-4518 https://github.com/vkb1/manufacturing-ai-suite.git ~/manufacturing-ai-suite
   cd ~/manufacturing-ai-suite
   git sparse-checkout set industrial-edge-insights-multimodal
   ```

   The app root used in the rest of this guide is `~/manufacturing-ai-suite/industrial-edge-insights-multimodal`.

2. **Fill in `.env`** in the app root. `make check_env_variables` validates these values, and the `multimodal-deploy` skill stops if any are missing:

   | Variables | Rule |
   | --- | --- |
   | `INFLUXDB_USERNAME/PASSWORD`, `VISUALIZER_GRAFANA_USER/PASSWORD`, `MTX_WEBRTCICESERVERS2_0_USERNAME/PASSWORD`, `S3_STORAGE_USERNAME/PASSWORD`, `SEAWEEDFS_WEB_AUTH_USER/PASSWORD` | Usernames: letters only, at least 5 characters (`INFLUXDB_USERNAME` must not be `admin`). Passwords: alphanumeric, at least 10 characters, with at least one letter and one digit |
   | `MCP_USERNAME`, `MCP_PASSWORD` | Same rules. Required for `MCP=true`. The MCP server requires these (HTTP Basic auth) for `start_pipeline` and `stop_pipeline` |
   | `HOST_IP` | Leave at `127.0.0.1` for this guide |

   Use different MCP credentials per node, and keep them; you need them again in [section 7](#71-store-the-mcp-credentials-on-the-central-host).

3. **Check Docker access** for the deployment user:

   ```bash
   docker info >/dev/null && echo OK
   ```

---

## 4. Create one Hermes profile per node

Each profile is an isolated Hermes home on the central host whose terminal runs commands on one node over SSH. `--clone` copies the LLM provider settings and keys from your current profile. Create the profiles **before** registering the MCP servers in section 7, so the node profiles don't inherit them.

```bash
for n in 1 2; do
  p="weld-node-$n"
  hermes profile create "$p" --clone --description "Runs multimodal-deploy on $p over SSH"
  hermes -p "$p" config set terminal.backend ssh
  hermes -p "$p" config set TERMINAL_SSH_HOST "$p"      # hostname or IP of the node
  hermes -p "$p" config set TERMINAL_SSH_USER deploy
  hermes -p "$p" config set terminal.timeout 3600       # model download and image pulls exceed the 180 s default
done
```

`TERMINAL_SSH_*` are saved to the profile's `.env`. Add `TERMINAL_SSH_KEY` or `TERMINAL_SSH_PORT` if you don't use the defaults.

Check that each profile reaches its node:

```bash
hermes -p weld-node-1 chat --oneshot -q "Run 'hostname && docker compose version' and show the output verbatim."
```

---

## 5. Install the `multimodal-deploy` skill

The skill lives in the repository at `industrial-edge-insights-multimodal/.github/skills/multimodal-deploy/`. Copy it into both node profiles:

```bash
SKILL_SRC=~/repos/manufacturing-ai-suite/industrial-edge-insights-multimodal/.github/skills/multimodal-deploy

for p in weld-node-1 weld-node-2; do
  install -d ~/.hermes/profiles/$p/skills/devops
  cp -r "$SKILL_SRC" ~/.hermes/profiles/$p/skills/devops/
  hermes -p "$p" skills list | grep multimodal-deploy
done
```

Adjust `SKILL_SRC` to where you cloned the repository on the central host.

The skill already contains everything this guide relies on: the preflight checks, the variant table, `make up_agentic MCP=true`, `scripts/smoke-check.sh` (which also probes `/mcp` with a read-only `tools/list`), and the rule that pipelines are only started after the user confirms.

### Approval policy for unattended runs

Hermes reviews potentially dangerous terminal commands before running them (`approvals.mode: smart` by default). A one-shot run has no one to answer an approval prompt. Do the first deployment on each node interactively ([section 6.1](#61-first-deployment-interactive)). For later unattended runs, add a policy to each node profile with `hermes -p weld-node-1 config edit`:

```yaml
approvals:
  mode: smart
  smart_policy: |
    APPROVE make build, make up_agentic, make down, and make status (with or without MCP=true),
    and .github/skills/multimodal-deploy/scripts/smoke-check.sh, when run from
    ~/manufacturing-ai-suite/industrial-edge-insights-multimodal.
    ESCALATE anything that edits .env, uses sudo, or touches paths outside that directory.
```

Do not use `--yolo` or `approvals.mode: off` for this.

---

## 6. Deploy the app and MCP servers

The deployment prompt is the same for both nodes:

```bash
DEPLOY_PROMPT='In ~/manufacturing-ai-suite/industrial-edge-insights-multimodal, deploy the agentic variant with the MCP server (make up_agentic MCP=true), then run the smoke check. Do not edit .env; if a required credential is missing, stop and name it. Do not start or stop pipelines.'
```

### 6.1 First deployment (interactive)

Run each node once interactively, so you can answer approval prompts and watch the hardware check and model download:

```bash
hermes -p weld-node-1 chat -s multimodal-deploy -q "$DEPLOY_PROMPT"
hermes -p weld-node-2 chat -s multimodal-deploy -q "$DEPLOY_PROMPT"
```

On a terminal, `-q` submits the prompt as the first turn and keeps the session open.

### 6.2 Later deployments (both nodes in parallel)

```bash
mkdir -p ~/.hermes/logs/weld-fleet
pids=()
for n in 1 2; do
  hermes -p "weld-node-$n" chat -s multimodal-deploy --oneshot -q "$DEPLOY_PROMPT" \
    > ~/.hermes/logs/weld-fleet/weld_node$n.deploy.log 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || echo "a deployment run failed; check the logs"; done
```

`--oneshot` answers and exits. Its exit code reports whether the agent turn completed, not whether the app is healthy, so always read the log or run the MCP check in section 7.

### What to expect

- `make status` lists the stack plus the `multimodal-mcp-server` container.
- The smoke check prints `OK: https://127.0.0.1:3000/mcp answered tools/list`.
- **No data is processed yet.** With `MCP=true`, the weld classification pipeline does not auto-start and the time-series config is not posted, so Grafana stays empty until `start_pipeline` is called ([section 8](#8-verify-and-operate)). This is expected.

---

## 7. Connect both MCP servers to the central Hermes

All commands in this section run on the central host in the **default** profile.

### 7.1 Store the MCP credentials on the central host

The MCP server expects `Authorization: Basic <base64(MCP_USERNAME:MCP_PASSWORD)>` for `start_pipeline` and `stop_pipeline`. Store one value per node in `~/.hermes/.env` without echoing the password or passing it on a command line:

```bash
for n in 1 2; do
  read -rp  "MCP_USERNAME for weld-node-$n: " u
  read -rsp "MCP_PASSWORD for weld-node-$n: " p; echo
  printf 'WELD_NODE%s_MCP_BASIC=%s\n' "$n" "$(printf '%s:%s' "$u" "$p" | base64 -w0)" >> ~/.hermes/.env
  unset u p
done
chmod 600 ~/.hermes/.env
```

Base64 is encoding, not encryption. The SSH tunnel and the file permissions protect the value.

### 7.2 Tunnel unit

Create `~/.config/systemd/user/weld-tunnel@.service`:

```ini
[Unit]
Description=SSH tunnel to multimodal nginx (%i)
After=network-online.target

[Service]
EnvironmentFile=%h/.config/weld-tunnels/%i.env
ExecStart=/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L ${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} ${NODE}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Keep the tunnels running after you log out:

```bash
loginctl enable-linger "$USER"
```

### 7.3 Connect script

Save as `~/.hermes/skills/devops/weld-fleet/scripts/connect-weld-node.sh` (the `weld-fleet` skill in [section 9](#9-one-command-for-the-whole-fleet) reuses it) and run `chmod 0755` on it. For one node it starts the tunnel, fetches the node's current nginx certificate, waits for `/mcp` to answer, and registers the server in Hermes. It validates its inputs so an agent cannot pass arbitrary shell through it.

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 <user@host> <local-port> <server-name>" >&2; exit 2; }
[[ $# -eq 3 ]] || usage
target="$1" port="$2" name="$3"
remote_port="${WELD_REMOTE_PORT:-3000}"   # GRAFANA_PORT in the node's .env

[[ $target =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || usage
[[ $port =~ ^[0-9]{4,5}$ ]] && (( port >= 1024 && port <= 65535 )) || usage
[[ $remote_port =~ ^[0-9]{2,5}$ ]] || usage
[[ $name =~ ^weld_node[0-9]+$ ]] || usage

env_var="${name^^}_MCP_BASIC"
grep -q "^${env_var}=" "$HOME/.hermes/.env" 2>/dev/null \
  || { echo "[$name] add $env_var to ~/.hermes/.env first" >&2; exit 1; }

# 1. Tunnel: localhost:<port> on this host -> 127.0.0.1:<remote_port> on the node.
install -d "$HOME/.config/weld-tunnels"
printf 'LOCAL_PORT=%s\nREMOTE_PORT=%s\nNODE=%s\n' "$port" "$remote_port" "$target" \
  > "$HOME/.config/weld-tunnels/$name.env"
systemctl --user daemon-reload
systemctl --user enable "weld-tunnel@$name"
systemctl --user restart "weld-tunnel@$name"

# 2. nginx regenerates its self-signed certificate (CN=localhost) on every deploy, so fetch the current one.
cert_dir="$HOME/.hermes/certs"
install -d -m 0700 "$cert_dir"
cert="$cert_dir/$name.pem"
ssh "$target" docker exec nginx_proxy cat /opt/nginx/certs/cert.pem > "$cert.tmp"
openssl x509 -in "$cert.tmp" -noout
mv "$cert.tmp" "$cert"

# 3. Wait until /mcp answers a read-only tools/list.
url="https://localhost:${port}/mcp"
code=000
for _ in {1..60}; do
  code="$(curl -s --cacert "$cert" -o /dev/null -w '%{http_code}' -X POST "$url" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || true)"
  [[ $code == 200 ]] && break
  sleep 5
done
[[ $code == 200 ]] || { echo "[$name] $url not ready (HTTP $code)" >&2; exit 1; }

# 4. Register (or refresh) the server in the default Hermes profile.
hermes config set "mcp_servers.$name.url" "$url"
hermes config set "mcp_servers.$name.ssl_verify" "$cert"
hermes config set "mcp_servers.$name.headers.Authorization" "Basic \${$env_var}"
hermes config set "mcp_servers.$name.tools.include" \
  '["describe","list_insights_data","explain","run_agent","get_run_results","start_pipeline","stop_pipeline"]'
echo "[$name] MCP server on $target registered as $url"
```

Run it for both nodes:

```bash
S=~/.hermes/skills/devops/weld-fleet/scripts/connect-weld-node.sh
"$S" deploy@weld-node-1 13001 weld_node1
"$S" deploy@weld-node-2 13002 weld_node2
```

Run it again after every redeploy, because the certificate changes.

### 7.4 Resulting configuration

`~/.hermes/config.yaml` (default profile) now contains:

```yaml
mcp_servers:
  weld_node1:
    url: "https://localhost:13001/mcp"
    ssl_verify: "~/.hermes/certs/weld_node1.pem"
    headers:
      Authorization: "Basic ${WELD_NODE1_MCP_BASIC}"
    tools:
      include: ["describe", "list_insights_data", "explain", "run_agent", "get_run_results", "start_pipeline", "stop_pipeline"]
  weld_node2:
    url: "https://localhost:13002/mcp"
    ssl_verify: "~/.hermes/certs/weld_node2.pem"
    headers:
      Authorization: "Basic ${WELD_NODE2_MCP_BASIC}"
    tools:
      include: ["describe", "list_insights_data", "explain", "run_agent", "get_run_results", "start_pipeline", "stop_pipeline"]
```

The paths are written in full by the script. Hermes resolves `${WELD_NODE*_MCP_BASIC}` from `~/.hermes/.env` when it connects. The tools register per node:

| Tool | Acts on |
| --- | --- |
| `mcp__weld_node1__describe`, `…__start_pipeline`, `…__stop_pipeline`, `…__list_insights_data`, `…__run_agent`, `…__get_run_results`, `…__explain` | weld-node-1 |
| `mcp__weld_node2__…` (same tools) | weld-node-2 |

---

## 8. Verify and operate

Start a new Hermes session (or run `/reload-mcp`) so the servers load, then check both:

```bash
hermes mcp test weld_node1
hermes mcp test weld_node2
hermes chat --oneshot -q "Call mcp__weld_node1__describe and mcp__weld_node2__describe and summarize each result."
```

### Start processing

`start_pipeline` and `stop_pipeline` change live processing, so confirm before calling them. In an interactive chat:

> Start the weld pipeline on weld_node1 with vision on CPU and time series on CPU.

The agent calls `mcp__weld_node1__start_pipeline` with `vision_inf_device: CPU` (`CPU`, `GPU`, or `NPU`) and `time_series_inf_device: CPU` (`CPU` or `GPU`). The tool uploads the UDF package, posts the time-series config, waits up to 120 s for the `weld_anomaly_detector` task, and starts DL Streamer.

### Query results

Allow some time for data to flow, then:

> Show the latest 10 insights from weld_node1, then run the agent on weld_node1 over the last 1m and fetch the run results.

This uses `list_insights_data`, `run_agent` (`time_range`: `30s`, `1m`, `5m`, `10m`, or `30m`), and `get_run_results`.

### Open the UI

The same tunnel serves the app UI. On the central host, open `https://localhost:13001/` (weld-node-1) or `https://localhost:13002/` (weld-node-2) and accept the self-signed certificate. From another machine, forward the port over SSH to the central host first.

### Chat in a web UI (optional)

Hermes' built-in dashboard has a basic chat. For a better chat, use the community [Hermes WebUI](https://github.com/nesquena/hermes-webui) (MIT). It reads the same `~/.hermes` as the CLI and shows:

- profiles (`default`, `weld-node-1`, `weld-node-2`), with a profile picker in the message box
- skills, which you can browse, edit, and turn on or off
- MCP servers and their tools, read-only (add or edit servers in `config.yaml` as in section 7)
- the tools available to each session
- CLI session history

MCP tool calls such as `mcp__weld_node1__describe` work from its chat. It is not affiliated with Nous Research.

Install it on the central host, pinned to a release tag and with a password. [`hermes-webui.sh`](hermes-webui.sh) does this for you:

```bash
./hermes-webui.sh            # install if needed, then start; asks for a password on first run
./hermes-webui.sh status     # also: stop | restart | logs | install (updates to the pinned tag)
```

The script runs these steps:

```bash
git clone https://github.com/nesquena/hermes-webui.git ~/hermes-webui
cd ~/hermes-webui
git checkout v0.52.492
read -rsp 'WebUI password: ' pw; echo
umask 077
printf 'HERMES_WEBUI_HOST=127.0.0.1\nHERMES_WEBUI_PORT=8787\nHERMES_WEBUI_PASSWORD=%s\n' "$pw" > .env
unset pw
./ctl.sh start      # also: ./ctl.sh status | logs | stop
```

`ctl.sh` finds the Hermes Agent install and its Python. It writes its PID and log to `~/.hermes/webui.pid` and `~/.hermes/webui.log`, and keeps WebUI sessions in `~/.hermes/webui/`.

Open `http://127.0.0.1:8787/` on the central host. From another machine, forward the port over SSH rather than binding to a network address:

```bash
ssh -N -L 8787:127.0.0.1:8787 <user>@<central-host>
```

To listen on all interfaces instead, for example on a trusted lab network, set the bind address once. The script saves it in `.env` and prints a warning. Switch back with `HERMES_WEBUI_HOST=127.0.0.1`:

```bash
HERMES_WEBUI_HOST=0.0.0.0 ./hermes-webui.sh start
```

The UI is plain HTTP, so the password and chats cross the network unencrypted. Limit the port with a firewall, or put a TLS reverse proxy in front.

Keep the password set even though it listens only on loopback. WebUI includes a terminal and file access as your user, so on a shared host any local account could otherwise use it.

---

## 9. One command for the whole fleet

The `weld-fleet` skill on the central host (default profile) chains sections 6.2 and 7: it runs `multimodal-deploy` on each node through its profile, connects the MCP servers, and verifies them.

Layout:

```text
~/.hermes/skills/devops/weld-fleet/
├── SKILL.md
└── scripts/
    ├── fleet.sh
    └── connect-weld-node.sh   # from section 7.3
```

`scripts/fleet.sh` holds the node table, so the agent passes only node names:

```bash
#!/usr/bin/env bash
set -euo pipefail

declare -A PROFILE=([weld_node1]=weld-node-1 [weld_node2]=weld-node-2)
declare -A SSH_TARGET=([weld_node1]=deploy@weld-node-1 [weld_node2]=deploy@weld-node-2)
declare -A PORT=([weld_node1]=13001 [weld_node2]=13002)
APP_DIR='~/manufacturing-ai-suite/industrial-edge-insights-multimodal'
PROMPT="In $APP_DIR, deploy the agentic variant with the MCP server (make up_agentic MCP=true), then run the smoke check. Do not edit .env; if a required credential is missing, stop and name it. Do not start or stop pipelines."

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="$HOME/.hermes/logs/weld-fleet"
install -d "$log_dir"

[[ $# -ge 1 ]] || set -- "${!PROFILE[@]}"
for n in "$@"; do
  [[ -n ${PROFILE[$n]+x} ]] || { echo "unknown node: $n" >&2; exit 2; }
done

declare -A pid
for n in "$@"; do
  hermes -p "${PROFILE[$n]}" chat -s multimodal-deploy --oneshot -q "$PROMPT" > "$log_dir/$n.deploy.log" 2>&1 &
  pid[$n]=$!
done

rc=0
for n in "$@"; do
  if ! wait "${pid[$n]}"; then
    echo "[$n] deployment run failed; see $log_dir/$n.deploy.log"; rc=1; continue
  fi
  if "$script_dir/connect-weld-node.sh" "${SSH_TARGET[$n]}" "${PORT[$n]}" "$n"; then
    echo "[$n] app and MCP server up"
  else
    echo "[$n] MCP server not reachable; see $log_dir/$n.deploy.log"; rc=1
  fi
done
exit "$rc"
```

`SKILL.md`:

```markdown
---
name: weld-fleet
description: Deploys the multimodal weld defect detection app with its MCP server (make up_agentic MCP=true) on weld_node1 and weld_node2 through the multimodal-deploy skill, then connects both MCP servers to this Hermes.
---
# Weld fleet deploy

## Procedure
1. Use the node names in the request (`weld_node1`, `weld_node2`). If none are named, deploy both. Refuse any other name.
2. From this skill's directory, run `scripts/fleet.sh <names>` and wait for it to finish. It can take many minutes on a first deployment.
3. If it exits non-zero, report which nodes failed and the last 40 lines of each failed node's log in `~/.hermes/logs/weld-fleet/`. Do not retry automatically.
4. The current session loaded its MCP tools before the servers were registered. Verify in a fresh process:
   `hermes chat --oneshot -q "Call mcp__<name>__describe for each of: <names that succeeded>. Summarize each result."`
5. Report a table: node, deployment result, MCP describe result.
6. Remind the user that pipelines do not auto-start in MCP mode. Do not call `start_pipeline` or `stop_pipeline` unless the user asks for it in this conversation and confirms the node and devices.

Do not run any other terminal commands. Never print or log MCP credentials.
```

Run it:

```bash
chmod 0755 ~/.hermes/skills/devops/weld-fleet/scripts/*.sh
hermes -s weld-fleet chat -q "Deploy the weld app with the MCP server on both nodes."
```

To redeploy one node: `hermes -s weld-fleet chat -q "Redeploy weld_node2."`

On a schedule, with [`hermes cron`](hermes-setup.md#scheduled-and-recurring-tasks-with-hermes-cron) (the node profiles need the approval policy from [section 5](#approval-policy-for-unattended-runs)):

```bash
hermes cron create "0 3 * * 1" \
  "Use the weld-fleet skill to redeploy weld_node1 and weld_node2, then report the status table." \
  --skill weld-fleet --name "Weekly weld fleet redeploy"
```

---

## 10. Tear down

Stop processing and remove the stack on a node (this also deletes the app's InfluxDB and Grafana volumes):

```bash
hermes -p weld-node-1 chat -s multimodal-deploy -q \
  "In ~/manufacturing-ai-suite/industrial-edge-insights-multimodal, run make down MCP=true."
```

Then remove the central-side wiring for that node:

```bash
systemctl --user disable --now weld-tunnel@weld_node1
hermes config unset mcp_servers.weld_node1
rm -f ~/.hermes/certs/weld_node1.pem
```

---

## 11. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Setup script: `cannot use Docker` right after adding the user to the `docker` group | An existing SSH connection (for example a `ControlMaster` socket from your `~/.ssh/config`) still uses the old group list. Close it (`ssh -O exit deploy@<ip>`) and rerun the script |
| Setup script: `Install these on <host> first` | The node is not `apt`-based. Install the listed packages yourself and rerun |
| Setup script: `sudo` fails without prompting | The script was not run from an interactive terminal. Run it directly in a terminal, not from a Hermes chat or cron |
| Setup script: `Local changes … block switching to migrate/pr-4518` | The node's existing clone has edits that conflict with the branch (usually `.env`). On the node, back up `.env`, run `git stash` in `~/manufacturing-ai-suite`, rerun the script, then restore your values |
| `check_hardware` fails | Not a Panther Lake / Core Ultra 3xx node. Use supported hardware; `PLATFORM_CHECK=false` is for CI/validation only |
| Deploy stops with "credential missing" | A required `.env` value is empty on the node. Edit `.env` on the node ([section 3](#3-prepare-the-nodes)), not through Hermes |
| One-shot deploy hangs or ends early | An approval prompt had no one to answer it. Run interactively once, or add the `smart_policy` from section 5 |
| A command is cut off after 3 minutes | `terminal.timeout` is at its default. Set it to `3600` in the node profile |
| `connect-weld-node.sh` reports HTTP `000` | Tunnel not up. Check `systemctl --user status weld-tunnel@weld_node1` and `ssh deploy@weld-node-1 true` |
| HTTP `404` on `/mcp` | The node was started without `MCP=true`, so nginx has no `/mcp` route. Redeploy with `make up_agentic MCP=true` |
| Hermes reports a TLS or certificate error after a redeploy | The certificate was regenerated. Rerun `connect-weld-node.sh` for that node |
| TLS error `CA cert does not include key usage extension` | Python 3.13+ applies strict X.509 checks that the app's simple self-signed certificate does not pass. Because the connection is to `localhost` and travels inside the SSH tunnel, you may set `ssl_verify: false` for that server as a deliberate exception |
| `start_pipeline` returns "Authentication required" | `WELD_NODE*_MCP_BASIC` does not match `MCP_USERNAME`/`MCP_PASSWORD` in that node's `.env`. Regenerate it (section 7.1) and restart Hermes |
| Grafana is empty after deployment | Expected in MCP mode until `start_pipeline` is called |
| `start_pipeline` reports the time-series task not enabled | The task did not come up within 120 s. Check `make status` on the node, then call `stop_pipeline` and retry |

---

## 12. Security notes

- **Nothing new is exposed on the network.** nginx listens on the node's loopback (`HOST_IP=127.0.0.1`), and the central host reaches it only through SSH. Keep it that way: the MCP server requires authentication only for `start_pipeline` and `stop_pipeline`; `describe`, `list_insights_data`, `explain`, `get_run_results`, and `run_agent` are unauthenticated.
- **Secrets stay out of chats and commands.** Node credentials are entered in the node's `.env`; the central MCP credentials live in `~/.hermes/.env` (mode `600`) and are referenced as `${VAR}`. Don't paste them into a Hermes chat.
- **Least privilege on the nodes.** The deployment user needs Docker access, which is root-equivalent. Use a dedicated account with key-only SSH, and don't give it `sudo`.
- **One deployment account on every node.** Use the same dedicated account name (for example `deploy`) on all nodes, so `hosts.yaml` needs it only once in `defaults`. Keep it a service account, separate from people's own logins. Lock its password after the key is installed (`sudo passwd -l deploy`), and allow it key-only SSH from the central host, for example with `from="<central-ip>"` in its `authorized_keys`. One shared key means one stolen key opens every node, so protect it on the central host and rotate it when people or hosts change. For larger fleets, use one key per line or site (`identity_file` per node), or SSH certificates. Create the account the same way everywhere, for example with cloud-init or Ansible, rather than by hand.
- **Bounded automation.** The scripts validate every argument and keep node addresses in a fixed table. The skills forbid other terminal commands and require confirmation before pipelines change. The approval policy only pre-approves the app's own `make` targets and smoke check.
- **TLS.** Prefer `ssl_verify` pointing at the fetched certificate. Disable verification only for the `localhost` tunnel endpoint, never for a network address.
- **Web UI.** If you use the optional Hermes WebUI (section 8), keep it on `127.0.0.1` with `HERMES_WEBUI_PASSWORD` set, reach it over SSH, and pin it to a release tag. It is third-party code that runs with your Hermes permissions, including a terminal. Bind it to `0.0.0.0` only on a trusted network, behind a firewall.

---

## 13. Manage the fleet with the MCP Fleet Orchestrator

Sections 3–9 wire each node into Hermes with profiles, systemd tunnels, and shell scripts. The [MCP Fleet Orchestrator](mcp-fleet-orchestrator/README.md) does the same work behind a single MCP server named `fleet`. You then onboard nodes, install skills, deploy the app and its MCP server, and work with every node's MCP server from one Hermes chat.

| | Sections 3–9 | Fleet orchestrator |
| --- | --- | --- |
| Node list | Fixed tables in `weld-fleet-setup.sh` and `fleet.sh` | SQLite inventory. Add nodes in chat with `register_node` |
| Hermes profiles per node | One per node, with an SSH terminal backend | None. The orchestrator runs fixed scripts over SSH |
| Skill install on nodes | Copied into each profile | `install_skill` copies it to `~/.fleet/skills/<skill>` and checks its SHA-256 |
| Tunnels | `weld-tunnel@<node>` systemd units, local ports `1300N` | Owned by the orchestrator, local ports `1400N` |
| Node MCP tools in Hermes | `mcp__<node>__<tool>` | `mcp__fleet__call_node_tool` / `fleet_call_tool`. Optionally also `mcp__<node>__<tool>` |

Choose one path for each node. The two paths use different tunnel ports. Both register optional Hermes entries named `mcp_servers.<node>` with credential `<NODE>_MCP_BASIC`, though, so give nodes managed by the orchestrator their own names (for example `weld_node3`). Otherwise, skip `register_node_in_hermes` for nodes already connected in section 7.

### 13.1 Install the orchestrator on the central host

Requirements: Python 3.11+, `ssh`, `git`, and key-based SSH to every node. The node prerequisites are the same as in [section 2](#2-prerequisites). Onboarding installs packages only when the deployment user has **passwordless** `sudo`. Without it, it reports what is missing and stops.

```bash
git clone https://github.com/vkb1/mcp-fleet-orchestrator.git
python3 -m venv ~/.local/share/fleet-orchestrator/venv
~/.local/share/fleet-orchestrator/venv/bin/pip install ./mcp-fleet-orchestrator
```

Point the orchestrator at the same repository and branch as the rest of this guide. Its default is upstream `main`, which may not contain the `multimodal-deploy` skill yet:

```bash
install -d -m 0700 ~/.config
cat > ~/.config/fleet-orchestrator.env <<'CONF'
FLEET_REPO_URL=https://github.com/vkb1/manufacturing-ai-suite.git
FLEET_REPO_BRANCH=migrate/pr-4518
CONF
chmod 600 ~/.config/fleet-orchestrator.env
```

Run it as a user service, so jobs and tunnels keep running between chat sessions:

```bash
install -D -m 0644 mcp-fleet-orchestrator/deploy/fleet-orchestrator.service \
  ~/.config/systemd/user/fleet-orchestrator.service
systemctl --user daemon-reload
systemctl --user enable --now fleet-orchestrator
loginctl enable-linger "$USER"
systemctl --user status fleet-orchestrator --no-pager
```

The service listens on `127.0.0.1:8765` and requires a bearer token. On first start it writes the token to `~/.fleet-orchestrator/api-token` (mode `600`). The service does not use your SSH agent. Either the node SSH key must have no passphrase, or you set `SSH_AUTH_SOCK` in `~/.config/fleet-orchestrator.env`.

See the [orchestrator README](mcp-fleet-orchestrator/README.md#configuration) for all settings (`FLEET_HOME`, `FLEET_TUNNEL_BASE_PORT`, `FLEET_DEPLOY_TIMEOUT`, `FLEET_STRICT_HOST_KEYS`, …).

### 13.2 Register the orchestrator with Hermes and install its skill

Store the token in `~/.hermes/.env` without printing it, register the `fleet` MCP server, and install the `fleet-orchestrator` skill, which tells the agent how to use the tools:

```bash
printf 'FLEET_API_TOKEN=%s\n' "$(cat ~/.fleet-orchestrator/api-token)" >> ~/.hermes/.env
chmod 600 ~/.hermes/.env
hermes config set mcp_servers.fleet.url "http://127.0.0.1:8765/mcp"
hermes config set mcp_servers.fleet.headers.Authorization 'Bearer ${FLEET_API_TOKEN}'
install -d ~/.hermes/skills/devops
cp -r mcp-fleet-orchestrator/skills/fleet-orchestrator ~/.hermes/skills/devops/
hermes mcp test fleet
```

`hermes mcp test fleet` should list tools such as `register_node`, `onboard_node`, `install_skill`, `deploy_app`, and `call_node_tool`. Start a chat with the skill loaded:

```bash
hermes -s fleet-orchestrator chat
```

All later steps are prompts in this chat. The agent calls `mcp__fleet__<tool>`. Long steps (`onboard_node`, `stage_models`, `deploy_app`, `teardown_app`) return a `job_id` right away, and the agent polls `get_job` until the job finishes.

### 13.3 Onboard the nodes

> Register 192.168.1.21 as weld_node3 and 192.168.1.22 as weld_node4, both tagged line1, SSH user deploy. Then onboard them.

| Step | Tool | What happens |
| --- | --- | --- |
| 1 | `register_node` | Adds the node to the inventory and tests key-based SSH. The node is not changed |
| 2 | *(you, if needed)* | If SSH fails, the agent shows an `ssh-copy-id -p <port> deploy@<host>` command. Run it in your own terminal and tell the agent when it is done. Never type passwords into the chat |
| 3 | `onboard_node` *(job)* | Installs missing packages (with passwordless `sudo` only) and checks Docker access. Clones the app on the configured branch. Fills **empty** `.env` credentials with random valid values. Pins `HOST_IP=127.0.0.1` and stores the node's MCP login in `~/.fleet-orchestrator/secrets.env` |

Ask for `skip_platform_check` only on CI/validation machines that are not Panther Lake. It writes `PLATFORM_CHECK=false`.

### 13.4 Onboard skills on the nodes

Skills come from the app's `.github/skills/skill-catalog.json` on the configured branch. The orchestrator keeps a sparse clone of that directory on the central host.

> Which skills are available for the multimodal app? Install multimodal-deploy on all line1 nodes.

- `list_skills` reads the catalog: name, description, and triggers.
- `install_skill` copies a skill to `~/.fleet/skills/<skill>` on a node and checks its SHA-256. If you don't name a skill, it installs the app's deploy skill (`multimodal-deploy`).
- `list_nodes` shows the installed skills for each node.

`deploy_app` installs `multimodal-deploy` by itself if it is missing, so this step is needed only to install other catalog skills or to refresh a skill after the branch changes.

### 13.5 Deploy the app and its MCP server with the skill

> Deploy the agentic app with the MCP server on all line1 nodes.

- `deploy_fleet` (by `tag` or `names`) starts one `deploy_app` job per node, in parallel. For a single node, the agent uses `deploy_app`.
- The default variant `agentic_mcp` is `make up_agentic MCP=true`. Other variants are `default`, `vllm`, and `agentic`.
- Each job follows the `multimodal-deploy` skill: preflight, the `make` target, `make status`, and the skill's smoke check. Then, for `agentic_mcp`, it connects the node's MCP server (see [13.6](#136-register-the-node-mcp-servers)).
- The first deployment pulls images and downloads models, which can take a long time. `FLEET_DEPLOY_TIMEOUT` (default `3600` s) limits each job.

If a job reports that the vLLM models are not staged, the agent asks you to accept the [model license](https://huggingface.co/unsloth/Qwen3.5-2B). After you accept, it runs `stage_models` with `accept_model_license=true` and deploys again:

> I accept the Qwen3.5-2B license. Stage the models on weld_node3 and redeploy it.

On success, the agent reports the node, the variant, and the node's MCP tools. Pipelines do not start on their own in MCP mode.

### 13.6 Register the node MCP servers

**Through the orchestrator (automatic).** After an `agentic_mcp` deployment, the orchestrator does what section 7 does by hand. It opens an SSH tunnel from `127.0.0.1:1400N` to the node's `127.0.0.1:3000`. It fetches the node's current nginx certificate over SSH and pins it. Then it waits for `/mcp` to answer `tools/list`. The node's MCP server can now be used through `mcp__fleet__call_node_tool`. Nothing else needs to be registered.

After a redeploy outside the orchestrator (for example `make up_agentic MCP=true` run on the node), nginx has a new certificate. Refresh the connection:

> Reconnect weld_node3's MCP server.

(`connect_node_mcp`)

**Directly in Hermes (optional).** To also get native `mcp__<node>__<tool>` tools, as in section 7:

> Register weld_node3 in Hermes.

`register_node_in_hermes` writes `WELD_NODE3_MCP_BASIC` to `~/.hermes/.env` (mode `600`). It then sets `mcp_servers.weld_node3` with the tunnel URL, the pinned certificate as `ssl_verify`, `Authorization: Basic ${WELD_NODE3_MCP_BASIC}`, and an allow-list of the app's tools. The tools appear in **new** Hermes sessions. They depend on the orchestrator's tunnel, so keep the service running.

### 13.7 Work with the node MCP servers

Only the app's own tools can be called: `describe`, `list_insights_data`, `explain`, `run_agent`, `get_run_results`, `start_pipeline`, and `stop_pipeline`.

| Request | Tool used |
| --- | --- |
| "What tools does weld_node3's MCP server have?" | `list_node_tools` |
| "Describe every node on line1." | `fleet_call_tool` with `describe` and `tag: line1` |
| "Start the weld pipeline on weld_node4 with vision on GPU and time series on CPU." | `call_node_tool` with `start_pipeline`. The agent confirms the node and devices first, then passes `confirm=true` |
| "Show the latest 10 insights from weld_node4." | `call_node_tool` with `list_insights_data` |
| "Run the agent over the last 1m on weld_node4 and fetch the results." | `run_agent` (`time_range`: `30s`, `1m`, `5m`, `10m`, or `30m`), then `get_run_results` |
| "Stop the pipeline on all line1 nodes." | `fleet_call_tool` with `stop_pipeline`, after confirmation |
| "Status of weld_node3? Any jobs running?" | `node_status`, `list_nodes`, `list_jobs` |

Without a chat, for example from cron, use `--oneshot`:

```bash
hermes -s fleet-orchestrator chat --oneshot -q "Describe every node tagged line1 and summarize the result as a table."
```

### 13.8 Tear down and remove a node

> Tear down weld_node3, then remove it from the fleet.

- `teardown_app` *(job, needs `confirm=true`)* runs `make down MCP=true`. It also deletes the app's InfluxDB and Grafana volumes.
- `remove_node` *(needs `confirm=true`)* removes the node from the inventory and deletes its stored MCP credential, certificate, and tunnel. It does **not** stop the app, so run `teardown_app` first.
- If you used `register_node_in_hermes`, also remove the Hermes entry:

  ```bash
  hermes config unset mcp_servers.weld_node3
  sed -i '/^WELD_NODE3_MCP_BASIC=/d' ~/.hermes/.env
  ```

To remove the orchestrator itself:

```bash
hermes config unset mcp_servers.fleet
systemctl --user disable --now fleet-orchestrator
```

### 13.9 Troubleshooting the orchestrator

| Symptom | Cause and fix |
| --- | --- |
| `hermes mcp test fleet` returns `401` | `FLEET_API_TOKEN` in `~/.hermes/.env` does not match `~/.fleet-orchestrator/api-token`. Rewrite it (section 13.2) and restart Hermes |
| `hermes mcp test fleet` cannot connect | The service is not running. Check `systemctl --user status fleet-orchestrator` and `journalctl --user -u fleet-orchestrator` |
| `register_node` returns `ssh_ok: false` | Key-based SSH is not set up, or the service cannot use your SSH agent. Run the `ssh-copy-id` command it shows, or set `SSH_AUTH_SOCK` in `~/.config/fleet-orchestrator.env` |
| `onboard_node` fails with a `sudo` blocker | The deployment user has no passwordless `sudo`. Install the missing packages and add the user to the `docker` group yourself (section 3), then onboard again |
| `skill catalog not found` | The configured branch has no `.github/skills/skill-catalog.json`. Set `FLEET_REPO_URL`/`FLEET_REPO_BRANCH` (section 13.1) and restart the service |
| Job fails with "vLLM models are not staged" | Accept the license and run `stage_models` (section 13.5) |
| Node MCP calls fail with a TLS error after a redeploy | The certificate was regenerated. Ask for `connect_node_mcp` on that node |
| Job log | `get_job` returns the last log lines. Full logs are in `~/.fleet-orchestrator/logs/` |

The orchestrator's security model is described in its [README](mcp-fleet-orchestrator/README.md#security-model). Like sections 3–9, it keeps node endpoints on loopback behind SSH tunnels and keeps secrets out of chats. It also requires `confirm=true` for pipeline changes and destructive actions.
