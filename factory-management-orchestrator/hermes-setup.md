# Mastering Hermes Agent: Installation, Multi-Node Deployment, and Tool Integration

This guide covers the full lifecycle of [Hermes Agent](https://github.com/NousResearch/hermes-agent), the open-source, self-improving AI agent from Nous Research:

1. [Installation and initial setup](#1-installation-and-initial-setup)
2. [Connecting external tools with MCP](#2-connecting-external-tools-with-the-model-context-protocol-mcp)
3. [Multi-node deployments with skills, delegation, profiles, Kanban, and node-local MCP servers](#3-multi-node-operations-orchestrating-parallel-deployments)
4. [Skill discovery and automated invocation](#4-skill-discovery-and-automated-invocation)
5. [The CLI and graphical interfaces](#5-the-hermes-cli-and-graphical-interfaces)

Official documentation: <https://hermes-agent.nousresearch.com/docs/>

---

## 1. Installation and Initial Setup

Hermes Agent runs on a local machine (Linux, macOS, native Windows, or WSL2), a cloud VPS, or through one-click templates offered by several cloud providers. The installer handles most dependencies.

### Prerequisites

- **Operating system:** Linux, macOS, WSL2, or native Windows (PowerShell).
- **Hardware:** At least 4 GB RAM. A GPU is recommended only if you run local models.
- **Model access:** An API key from a provider such as Nous Portal, OpenRouter, OpenAI, or Anthropic, or a local endpoint such as Ollama.

### Step-by-step installation

1. **Run the installer.** It installs Python, Node.js, and the other dependencies, and puts the `hermes` command on your `PATH`.

   Linux, macOS, WSL2:

   ```bash
   curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
   ```

   Native Windows (PowerShell):

   ```powershell
   iex (irm https://hermes-agent.nousresearch.com/install.ps1)
   ```

2. **Reload your shell** (Linux/macOS/WSL2) so `hermes` is on your `PATH`:

   ```bash
   source ~/.bashrc   # or: source ~/.zshrc
   ```

3. **Run the setup wizard.** The installer launches it automatically; you can rerun it at any time:

   ```bash
   hermes setup
   ```

   The wizard asks you to:

   - **Choose an LLM provider:** Nous Portal, OpenRouter, OpenAI, Anthropic, or a custom endpoint (for example, Ollama).
   - **Enter your API key** for that provider.
   - **Select a default model.** Pick one with a context window of at least 64K tokens for complex tool-use workflows.

   > **Tip:** `hermes setup --portal` signs in to Nous Portal via OAuth and configures models plus the Tool Gateway (web search, image generation, TTS, cloud browser) in one step.

4. **Verify the installation:**

   ```bash
   hermes --version
   hermes doctor
   ```

Several cloud providers (for example, Hostinger, Alibaba Cloud, and Tencent Cloud) offer one-click VPS templates with Hermes Agent preinstalled.

---

## 2. Connecting External Tools with the Model Context Protocol (MCP)

The **Model Context Protocol (MCP)** is an open standard that lets Hermes use tools hosted outside Hermes itself. Hermes reads MCP server definitions from the `mcp_servers` block in `~/.hermes/config.yaml`.

There are two kinds of MCP servers:

- **stdio servers:** local subprocesses that Hermes starts and talks to over stdin/stdout.
- **HTTP servers:** remote endpoints Hermes connects to by URL.

Both use JSON-RPC 2.0. Hermes registers each server's tools as `mcp_<server_name>_<tool_name>` to avoid name collisions with built-in tools.

### Using the official MCP catalog

Hermes ships a curated catalog of Nous-reviewed MCP servers. Entries are disabled until you install them.

```bash
hermes mcp                   # interactive picker: install, enable, disable, uninstall
hermes mcp catalog           # plain-text list (scriptable)
hermes mcp install linear    # install an entry by name
hermes mcp login linear      # complete OAuth for servers that need it
hermes mcp configure linear  # change which of the server's tools are enabled
```

`hermes mcp install <name>` prompts for any required credentials, lets you pick which tools to enable, and updates `config.yaml`. Read an entry's manifest (shown at install time) before installing, because installing runs that entry's setup commands.

### Creating and registering a custom MCP server

Both examples below use [FastMCP](https://gofastmcp.com/), a Python framework for MCP servers and clients. It builds on the official `mcp` SDK and adds authentication providers, server composition and proxying, OpenAPI-to-MCP generation, an in-memory test client, and a CLI.

```bash
python -m venv venv && source venv/bin/activate
pip install fastmcp
```

FastMCP derives each tool's name from the function name, its description from the docstring, and its input schema from the type hints.

#### Option 1: Remote HTTP server (to-do list)

Use this when the tools must be reachable over the network. The `http` transport is MCP Streamable HTTP.

`todo_server.py`:

```python
from fastmcp import FastMCP

mcp = FastMCP("todo")
todo_items: list[str] = []


@mcp.tool
def todo_add_item(item: str) -> str:
    """Add an item to the to-do list."""
    todo_items.append(item)
    return f"Added: {item}"


@mcp.tool
def todo_list_items() -> list[str]:
    """Return all items on the to-do list."""
    return todo_items


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=5001, path="/mcp")
```

Start it with `python todo_server.py` (or `fastmcp run todo_server.py --transport http --port 5001`), then register it in `~/.hermes/config.yaml`:

```yaml
mcp_servers:
  todo_server:
    url: "http://localhost:5001/mcp"
    tools:
      include: ["todo_add_item", "todo_list_items"]
```

`tools.include` uses the server's own tool names. In Hermes the tools appear as `mcp_todo_server_todo_add_item` and `mcp_todo_server_todo_list_items`.

> **Security:** This example has no authentication. Before exposing it beyond `localhost`, add one of FastMCP's [auth providers](https://gofastmcp.com/servers/auth/authentication) (bearer token/JWT verification or OAuth) via `FastMCP("todo", auth=...)`, and pass the token from Hermes with `headers` as shown in [Managing MCP servers from the CLI](#managing-mcp-servers-from-the-cli).

#### Option 2: Local stdio server (current time)

Use this for local tools. Hermes starts the script as a subprocess.

`mcp_time_server.py`:

```python
from datetime import datetime

from fastmcp import FastMCP

mcp = FastMCP("time")


@mcp.tool
def get_current_time() -> str:
    """Get the current local time."""
    return f"The current time is: {datetime.now().isoformat()}"


if __name__ == "__main__":
    mcp.run()  # stdio is the default transport
```

Register it with `command` and `args` instead of `url`. Use the Python interpreter from the virtual environment where `fastmcp` is installed:

```yaml
mcp_servers:
  time:
    command: "/path/to/venv/bin/python"
    args: ["/path/to/mcp_time_server.py"]
```

Restart Hermes, or run `/reload-mcp` in chat, to load the new `mcp_time_get_current_time` tool.

### Managing MCP servers from the CLI

`hermes config` edits `config.yaml` without opening it, which is useful for automation.

```bash
# Add an HTTP server
hermes config set mcp_servers.my_api.url "https://mcp.example.com/mcp"

# Store the secret in ~/.hermes/.env and reference it from config.yaml
hermes config set MY_API_KEY "your-secret-token"
hermes config set mcp_servers.my_api.headers.Authorization 'Bearer ${MY_API_KEY}'

# Inspect, update, or remove servers
hermes config get mcp_servers
hermes config set mcp_servers.my_api.url "https://new-mcp.example.com/mcp"
hermes config unset mcp_servers.my_api
```

`${VAR}` placeholders in `url`, `headers`, `command`, and `args` are resolved from environment variables (including `~/.hermes/.env`) when Hermes connects to the server. The single quotes stop your shell from expanding `${MY_API_KEY}` itself.

---

## 3. Multi-Node Operations: Orchestrating Parallel Deployments

A **skill** is a directory containing a `SKILL.md` file that documents a reusable procedure. Hermes can create skills from experience and follow them on request. Combined with delegation or profiles, skills let you run deployments on several nodes in parallel.

The examples below deploy a Dockerized Flask app. They assume:

- passwordless SSH access from the Hermes host to each node, and
- Docker installed on each node, with the app source at `/path/to/app`.

### Pattern 1: Stateless parallelism with `delegate_task`

Use this for short-lived parallel work. The main agent spawns isolated subagents, each with a fresh context, and waits for all of them to finish.

#### 1. Create a deployment skill per node

`~/.hermes/skills/deploy-node1/SKILL.md`:

```markdown
---
name: deploy-node1
description: Deploys the Flask app to web-node-1 over SSH.
---
# Deploy to web-node-1

## Procedure
Run this command and report the result:

    ssh user@web-node-1 'cd /path/to/app && docker build -t app . && { docker rm -f app || true; } && docker run -d --name app -p 5001:5000 app'
```

`~/.hermes/skills/deploy-node2/SKILL.md`:

```markdown
---
name: deploy-node2
description: Deploys the Flask app to web-node-2 over SSH.
---
# Deploy to web-node-2

## Procedure
Run this command and report the result:

    ssh user@web-node-2 'cd /path/to/app && docker build -t app . && { docker rm -f app || true; } && docker run -d --name app -p 5002:5000 app'
```

The `{ ...; }` group ensures that a failed `docker build` stops the deployment instead of replacing the running container with a stale image.

#### 2. Launch the parallel deployment

In a Hermes chat, ask the agent to deploy to both nodes in parallel. It uses `delegate_task` to run one subagent per node:

> Deploy the Flask app to web-node-1 and web-node-2 in parallel using the deploy-node1 and deploy-node2 skills.

### Pattern 2: Stateful orchestration with profiles and the Kanban board

Use this for durable, long-running work where each node needs its own persistent agent and configuration. The Kanban board is stored in SQLite at `~/.hermes/kanban.db`.

#### 1. Create a profile for each node

A profile is a separate Hermes home (its own `config.yaml`, `.env`, memory, skills, and gateway). Each profile also gets a command alias with the same name, so `web-node-1 <command>` is equivalent to `hermes -p web-node-1 <command>`.

```bash
hermes profile create web-node-1 --description "Deploys apps on web-node-1"
hermes profile create web-node-2 --description "Deploys apps on web-node-2"
```

`--description` tells the Kanban orchestrator what each worker is for.

#### 2. Point each profile's terminal at its node over SSH

Edit `~/.hermes/profiles/web-node-1/config.yaml`:

```yaml
terminal:
  backend: ssh
  ssh_host: "ip_for_web_node_1"
  # ... other SSH settings
```

Edit `~/.hermes/profiles/web-node-2/config.yaml`:

```yaml
terminal:
  backend: ssh
  ssh_host: "ip_for_web_node_2"
  # ... other SSH settings
```

#### 3. Create one generic deployment skill

Because each profile already runs its commands on its own node, both can share one skill. Profiles have separate skill directories, so install it in each profile:

`~/.hermes/profiles/web-node-1/skills/devops/deploy-flask-app/SKILL.md` (and the same file under `web-node-2`):

```markdown
---
name: deploy-flask-app
description: Deploys the latest version of the "Hello World" Flask web application using Docker.
---
# Deploy Flask App

## Procedure
1. Pull the latest code: `git pull origin main`
2. Build the image: `docker build -t hello-world-app .`
3. Stop on build failure. Otherwise remove the old container: `docker rm -f hello-world-container || true`
4. Run the new container: `docker run -d --name hello-world-container -p 5000:5000 hello-world-app`
```

#### 4. Orchestrate with the Kanban board

Start each worker's gateway so it can pick up tasks:

```bash
web-node-1 gateway start
web-node-2 gateway start
```

Then create and assign tasks:

```bash
# Initialize the board (first time only)
hermes kanban init

# One task per node
hermes kanban create "Deploy the flask app" --assignee web-node-1
hermes kanban create "Deploy the flask app" --assignee web-node-2
```

Each running gateway picks up its assigned task and runs the `deploy-flask-app` skill on its node.

### Pattern 3: Centralized Hermes with node-local MCP servers

Use this when one central Hermes agent should run skills on several nodes, and each node should expose only typed operations instead of accepting arbitrary shell commands.

- **Central Hermes host:** runs the only Hermes installation. It holds the LLM API keys, `config.yaml`, and all skills.
- **Nodes:** run only a small MCP server. No Hermes installation or API keys are needed on the nodes.

The central agent registers each node's MCP server under its own name, and its skills call that node's tools. The tool code runs on the node that hosts the MCP server, so a skill that calls `mcp_node1_*` tools always acts on web-node-1.

```text
Central Hermes host                         web-node-1 (MCP server only)
  skills  --> mcp_servers.node1 --SSH tunnel--> node_ops_server.py --> docker
          --> mcp_servers.node2 --SSH tunnel--> node_ops_server.py --> docker
                                            web-node-2 (MCP server only)
```

Steps 1–6 set this up by hand. [Step 7](#7-automate-bring-up-the-mcp-servers-and-deploy-from-one-skill) packages steps 2–4 and the deployment into one skill on the central host.

#### 1. Create the MCP server

Copy `node_ops_server.py` to both nodes and install FastMCP there (`pip install fastmcp` in a virtual environment).

`node_ops_server.py`:

```python
import socket
import subprocess

from fastmcp import FastMCP

APP_DIR = "/path/to/app"
IMAGE = "app"
CONTAINER = "app"

mcp = FastMCP("node-ops")


def _run(args: list[str], timeout: int = 900) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=APP_DIR, capture_output=True, text=True, timeout=timeout)


@mcp.tool
def deploy_app(host_port: int = 5000) -> str:
    """Build the app image and (re)start its container on this node."""
    if not 1024 <= host_port <= 65535:
        raise ValueError("host_port must be between 1024 and 65535")

    build = _run(["docker", "build", "-t", IMAGE, "."])
    if build.returncode != 0:
        return f"[{socket.gethostname()}] build failed; running container left unchanged:\n{build.stderr[-2000:]}"

    _run(["docker", "rm", "-f", CONTAINER])
    run = _run(["docker", "run", "-d", "--name", CONTAINER, "-p", f"{host_port}:5000", IMAGE])
    if run.returncode != 0:
        return f"[{socket.gethostname()}] run failed:\n{run.stderr[-2000:]}"
    return f"[{socket.gethostname()}] deployed container {run.stdout.strip()[:12]} on port {host_port}"


@mcp.tool
def app_status() -> str:
    """Report the status of the app container on this node."""
    ps = _run(["docker", "ps", "-a", "--filter", f"name=^{CONTAINER}$", "--format", "{{.Status}} {{.Ports}}"], timeout=30)
    return f"[{socket.gethostname()}] {ps.stdout.strip() or 'not running'}"


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=5001, path="/mcp")
```

The tools take only validated parameters and call `docker` with argument lists (no shell), and every result is prefixed with the node's hostname so you can confirm where it ran.

#### 2. Run the server as a service on both nodes

Create `node-ops-mcp.service`. Replace `deploy` with a non-root account on the node that can run `docker` (members of the `docker` group effectively have root access, so use a dedicated account):

```ini
[Unit]
Description=Node ops MCP server
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=deploy
WorkingDirectory=/path/to/mcp
ExecStart=/path/to/mcp/venv/bin/python node_ops_server.py
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

Install and start it on each node:

```bash
for node in web-node-1 web-node-2; do
  scp node-ops-mcp.service "user@${node}:/tmp/"
  ssh -t "user@${node}" 'sudo mv /tmp/node-ops-mcp.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now node-ops-mcp'
done
```

Check it with `ssh user@web-node-1 'systemctl status node-ops-mcp'`.

#### 3. Reach both servers from the central Hermes host

The servers listen on `127.0.0.1` only, so they are not exposed on the network. Forward a distinct local port on the central host to each node over SSH.

For a quick test:

```bash
ssh -fN -L 5101:127.0.0.1:5001 user@web-node-1
ssh -fN -L 5102:127.0.0.1:5001 user@web-node-2
```

For long-lived setups, run the tunnels as systemd user services so they reconnect automatically. Create `~/.config/systemd/user/mcp-tunnel@.service`:

```ini
[Unit]
Description=SSH tunnel to MCP server (%i)
After=network-online.target

[Service]
EnvironmentFile=%h/.config/mcp-tunnels/%i.env
ExecStart=/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L ${LOCAL_PORT}:127.0.0.1:5001 ${NODE}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Create one environment file per node, then enable both tunnels:

```bash
mkdir -p ~/.config/mcp-tunnels
printf 'LOCAL_PORT=5101\nNODE=user@web-node-1\n' > ~/.config/mcp-tunnels/node1.env
printf 'LOCAL_PORT=5102\nNODE=user@web-node-2\n' > ~/.config/mcp-tunnels/node2.env

systemctl --user daemon-reload
systemctl --user enable --now mcp-tunnel@node1 mcp-tunnel@node2
loginctl enable-linger "$USER"   # keep the tunnels running after you log out
```

`autossh` is a lighter alternative if you do not want systemd units.

> **Security:** If you bind the servers to a public interface instead of using SSH tunnels, serve them over HTTPS, add a FastMCP [auth provider](https://gofastmcp.com/servers/auth/authentication), and pass the token from Hermes with `headers` as shown in [Managing MCP servers from the CLI](#managing-mcp-servers-from-the-cli).

#### 4. Register both MCP servers in the central Hermes

Add one entry per node to `~/.hermes/config.yaml` on the central host:

```yaml
mcp_servers:
  node1:
    url: "http://127.0.0.1:5101/mcp"
    tools:
      include: ["deploy_app", "app_status"]
  node2:
    url: "http://127.0.0.1:5102/mcp"
    tools:
      include: ["deploy_app", "app_status"]
```

Or set the URLs from the CLI:

```bash
hermes config set mcp_servers.node1.url "http://127.0.0.1:5101/mcp"
hermes config set mcp_servers.node2.url "http://127.0.0.1:5102/mcp"
```

Restart Hermes or run `/reload-mcp`. The tools are registered per node:

| Tool | Runs on |
| --- | --- |
| `mcp_node1_deploy_app`, `mcp_node1_app_status` | web-node-1 |
| `mcp_node2_deploy_app`, `mcp_node2_app_status` | web-node-2 |

Verify that both nodes are reachable before you add skills:

```bash
hermes chat -q "Call mcp_node1_app_status and mcp_node2_app_status and show both results verbatim."
```

Each result must start with the hostname of the matching node. If a tool is missing, check the tunnel (`systemctl --user status mcp-tunnel@node1`) and the node service (`systemctl status node-ops-mcp`).

#### 5. Create the skills on the central host

All skills live only on the central host. Choose per-node skills, a generic multi-node skill, or both.

##### Option A: One skill per node

`~/.hermes/skills/mcp-deploy-node1/SKILL.md`:

```markdown
---
name: mcp-deploy-node1
description: Deploys the Flask app on web-node-1 using the node1 MCP server.
---
# Deploy to web-node-1 via MCP

## Procedure
1. Call `mcp_node1_deploy_app` with `host_port: 5001`.
2. If the result reports a failure, stop and report it.
3. Call `mcp_node1_app_status` and report the result.

Use only `mcp_node1_*` tools. Do not use the terminal or `mcp_node2_*` tools.
```

`~/.hermes/skills/mcp-deploy-node2/SKILL.md`:

```markdown
---
name: mcp-deploy-node2
description: Deploys the Flask app on web-node-2 using the node2 MCP server.
---
# Deploy to web-node-2 via MCP

## Procedure
1. Call `mcp_node2_deploy_app` with `host_port: 5002`.
2. If the result reports a failure, stop and report it.
3. Call `mcp_node2_app_status` and report the result.

Use only `mcp_node2_*` tools. Do not use the terminal or `mcp_node1_*` tools.
```

##### Option B: One skill for all nodes

`~/.hermes/skills/deploy-to-nodes/SKILL.md`:

```markdown
---
name: deploy-to-nodes
description: Deploys the Flask app to one or more nodes (node1, node2) through their MCP servers.
---
# Deploy to nodes via MCP

## Nodes
| Node  | Tools         | Host port |
| ----- | ------------- | --------- |
| node1 | `mcp_node1_*` | 5001      |
| node2 | `mcp_node2_*` | 5002      |

## Procedure
1. Deploy to the nodes named in the request. If none are named, use every node in the table. Refuse node names that are not in the table.
2. If there is more than one node, use `delegate_task` with one subagent per node so they run in parallel.
3. For each node `<N>`:
   1. Call `mcp_<N>_deploy_app` with that node's host port.
   2. If the result reports a failure, report it and stop work on that node.
   3. Call `mcp_<N>_app_status`.
4. Report a table with the node, the hostname from the tool result, and the final status.

Use only the `mcp_node1_*` and `mcp_node2_*` tools. Do not use the terminal.
```

To add a node, run an MCP server and a tunnel for it, register it as `node3`, and add a row to the table.

#### 6. Run the skills on the nodes

From a Hermes chat on the central host:

> Deploy the Flask app to node1 and node2 using the deploy-to-nodes skill.

Or with the per-node skills, in parallel (uses `delegate_task`, one subagent per node):

> Deploy the Flask app to both nodes in parallel using the mcp-deploy-node1 and mcp-deploy-node2 skills.

Non-interactively, for scripts and CI/CD:

```bash
hermes -s deploy-to-nodes chat -q "Deploy the app to node1 and node2."
hermes -s mcp-deploy-node1 chat -q "Deploy the app."
```

On a schedule, with [`hermes cron`](#scheduled-and-recurring-tasks-with-hermes-cron):

```bash
hermes cron create "0 2 * * *" \
  "Use the deploy-to-nodes skill to deploy the Flask app to node1 and node2, then report the status table." \
  --name "Nightly node deploy"
```

Check the hostname prefix in each result to confirm the skill ran on the intended node.

#### 7. Automate: bring up the MCP servers and deploy from one skill

This skill lives on the central host. For each node it installs and starts the MCP server over SSH, opens the tunnel, and registers the server with Hermes, then deploys the app through the new MCP tools. Running it again updates the server and redeploys.

Prerequisites:

- Passwordless SSH from the central host to each node.
- On each node: `python3-venv`, Docker, the app source in `APP_DIR`, a non-root service account (`deploy` by default) that can run `docker`, and passwordless `sudo` for the SSH user (the script uses `sudo -n` and fails instead of prompting).
- On the central host: the `deploy-to-nodes` skill from [step 5, Option B](#option-b-one-skill-for-all-nodes), and `loginctl enable-linger "$USER"` so the tunnels survive logout.

Skill layout:

```text
~/.hermes/skills/devops/bootstrap-and-deploy/
├── SKILL.md
├── scripts/
│   └── bootstrap-node.sh
└── assets/
    ├── node_ops_server.py        # the server from step 1
    ├── node-ops-mcp.service.in   # template below
    └── mcp-tunnel@.service       # the tunnel unit from step 3
```

`assets/node-ops-mcp.service.in` is the step 2 unit with placeholders that the script fills in:

```ini
[Unit]
Description=Node ops MCP server
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=@SVC_USER@
WorkingDirectory=@MCP_DIR@
ExecStart=@MCP_DIR@/venv/bin/python node_ops_server.py
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

`scripts/bootstrap-node.sh` does the work for one node. It validates its inputs so the agent cannot pass arbitrary shell through it:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 <user@host> <tunnel-port> <node-name>" >&2; exit 2; }
[[ $# -eq 3 ]] || usage
target="$1" port="$2" name="$3"
svc_user="${NODE_SVC_USER:-deploy}"
remote_dir="${NODE_MCP_DIR:-/opt/node-ops}"
fastmcp_spec="${FASTMCP_SPEC:-fastmcp}"   # pin in production, e.g. fastmcp==X.Y.Z

[[ $target =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || usage
[[ $port =~ ^[0-9]{4,5}$ ]] && (( port >= 1024 && port <= 65535 )) || usage
[[ $name =~ ^node[0-9]+$ ]] || usage
[[ $svc_user =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "invalid NODE_SVC_USER" >&2; exit 2; }
[[ $remote_dir =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "invalid NODE_MCP_DIR" >&2; exit 2; }
[[ $fastmcp_spec =~ ^fastmcp(==[0-9][0-9A-Za-z.]*)?$ ]] || { echo "invalid FASTMCP_SPEC" >&2; exit 2; }

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Install and (re)start the MCP server on the node.
tmp="$(ssh "$target" mktemp -d)"
scp -q "$skill_dir/assets/node_ops_server.py" "$target:$tmp/"
sed -e "s|@SVC_USER@|$svc_user|g" -e "s|@MCP_DIR@|$remote_dir|g" \
  "$skill_dir/assets/node-ops-mcp.service.in" | ssh "$target" "cat > $tmp/node-ops-mcp.service"

ssh "$target" bash -s -- "$tmp" "$svc_user" "$remote_dir" "$fastmcp_spec" <<'REMOTE'
set -euo pipefail
tmp="$1" svc_user="$2" dir="$3" spec="$4"
trap 'rm -rf "$tmp"' EXIT
sudo -n install -d -o "$svc_user" "$dir"
sudo -n install -m 0644 -o "$svc_user" "$tmp/node_ops_server.py" "$dir/node_ops_server.py"
[[ -x "$dir/venv/bin/python" ]] || sudo -n -u "$svc_user" python3 -m venv "$dir/venv"
sudo -n -u "$svc_user" "$dir/venv/bin/pip" install --quiet "$spec"
sudo -n install -m 0644 "$tmp/node-ops-mcp.service" /etc/systemd/system/node-ops-mcp.service
sudo -n systemctl daemon-reload
sudo -n systemctl enable node-ops-mcp
sudo -n systemctl restart node-ops-mcp
REMOTE

# 2. Open the tunnel from the central host.
install -d "$HOME/.config/systemd/user" "$HOME/.config/mcp-tunnels"
install -m 0644 "$skill_dir/assets/mcp-tunnel@.service" "$HOME/.config/systemd/user/"
printf 'LOCAL_PORT=%s\nNODE=%s\n' "$port" "$target" > "$HOME/.config/mcp-tunnels/$name.env"
systemctl --user daemon-reload
systemctl --user enable "mcp-tunnel@$name"
systemctl --user restart "mcp-tunnel@$name"

# 3. Wait until the MCP endpoint answers, then register it.
url="http://127.0.0.1:${port}/mcp"
code=000
for _ in {1..30}; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)"
  [[ $code != 000 ]] && break
  sleep 1
done
[[ $code != 000 ]] || { echo "[$name] MCP server not reachable at $url" >&2; exit 1; }

hermes config set "mcp_servers.$name.url" "$url"
echo "[$name] MCP server running on $target, registered as $url"
```

Make it executable with `chmod 0755 ~/.hermes/skills/devops/bootstrap-and-deploy/scripts/bootstrap-node.sh`.

`SKILL.md`:

```markdown
---
name: bootstrap-and-deploy
description: Brings up the node-ops MCP server on each node, registers it with this Hermes, and deploys the Flask app through it.
---
# Bring up MCP servers and deploy

## Nodes
| Name  | SSH target      | Tunnel port |
| ----- | --------------- | ----------- |
| node1 | user@web-node-1 | 5101        |
| node2 | user@web-node-2 | 5102        |

## Procedure
1. Select the nodes named in the request. If none are named, use every node in the table. Refuse names that are not in the table.
2. For each selected node, run this from the skill directory, using only the values from the table:
   `scripts/bootstrap-node.sh <SSH target> <Tunnel port> <Name>`
   If the script exits non-zero, report its output and skip that node in the next step.
3. Deploy through the new MCP servers. The current session loaded its MCP tools before they were registered, so start a fresh Hermes process:
   `hermes -s deploy-to-nodes chat -q "Deploy the app to <names of the nodes that succeeded>."`
4. Report, per node: whether the MCP server came up, and the deployment status table from step 3.

Do not run any other terminal commands.
```

Run it from the central host:

```bash
hermes -s bootstrap-and-deploy chat -q "Bring up the MCP servers on node1 and node2 and deploy the app."
```

If you prefer to keep the two phases separate, run them as two commands instead. The second command starts a fresh process, so it sees the servers registered by the first:

```bash
hermes -s bootstrap-and-deploy chat -q "Bring up the MCP servers on node1 and node2. Skip the deployment step."
hermes -s deploy-to-nodes chat -q "Deploy the app to node1 and node2."
```

#### Variant: one generic skill with profiles and Kanban

Combine this with [Pattern 2](#pattern-2-stateful-orchestration-with-profiles-and-the-kanban-board) while keeping everything on the central host. Create the `web-node-1` and `web-node-2` profiles on the central host, but leave their `terminal` backend at its default instead of SSH, because the MCP server handles node access. Register each node's server under the **same** name in its own profile. Each profile then sees only its own node's tools, and one skill works for both:

```bash
hermes -p web-node-1 config set mcp_servers.node.url "http://127.0.0.1:5101/mcp"
hermes -p web-node-2 config set mcp_servers.node.url "http://127.0.0.1:5102/mcp"
```

Install this skill in both profiles (`~/.hermes/profiles/<profile>/skills/devops/mcp-deploy/SKILL.md`):

```markdown
---
name: mcp-deploy
description: Deploys the Flask app on this profile's node using the node MCP server.
---
# Deploy via node MCP server

## Procedure
1. Call `mcp_node_deploy_app` with `host_port: 5000`.
2. If the result reports a failure, stop and report it.
3. Call `mcp_node_app_status` and report the result.
```

Then start both gateways on the central host and assign tasks as in Pattern 2:

```bash
web-node-1 gateway start
web-node-2 gateway start
hermes kanban create "Deploy the flask app with the mcp-deploy skill" --assignee web-node-1
hermes kanban create "Deploy the flask app with the mcp-deploy skill" --assignee web-node-2
```

---

## 4. Skill Discovery and Automated Invocation

### Managing skills

```bash
hermes skills list                 # list installed and learned skills
hermes skills show <skill_name>    # view a skill's details
hermes skills install <skill_name> # install a skill from the Skills Hub
```

In chat, `/skills` lists skills and `/<skill-name>` invokes one directly.

### Non-interactive execution

Hermes can run without an interactive session, which suits scripts and CI/CD pipelines.

Run a single prompt and exit:

```bash
hermes chat -q "What is on my to-do list?"
```

Load a skill before running the prompt:

```bash
hermes -s deploy-flask-app chat -q "Run the deployment for the hello world app."
```

For running skills on remote nodes from one central agent, see [Pattern 3](#pattern-3-centralized-hermes-with-node-local-mcp-servers).

### Scheduled and recurring tasks with `hermes cron`

Each cron job runs in a fresh, isolated session, so its prompt must be self-contained. Schedules can be cron expressions, intervals (`every 1h`), relative delays (`30m`), or ISO timestamps.

```bash
# Every Monday at 09:00
hermes cron create "0 9 * * 1" \
  "Generate a weekly summary of trending AI repos on GitHub and send it to Slack." \
  --name "Weekly AI Digest" \
  --deliver slack:#eng-digest
```

Manage jobs:

| Command | Description |
| --- | --- |
| `hermes cron list` | List all scheduled jobs. |
| `hermes cron run <name>` | Run a job immediately (useful for testing). |
| `hermes cron pause <name>` | Temporarily disable a job. |
| `hermes cron resume <name>` | Re-enable a paused job. |
| `hermes cron edit <name>` | Change a job's schedule, prompt, or options. |
| `hermes cron remove <name>` | Delete a job permanently. |

---

## 5. The Hermes CLI and Graphical Interfaces

### CLI cheat sheet

| Command | Description |
| --- | --- |
| `hermes` | Start an interactive chat. |
| `hermes setup` | Run the setup wizard. |
| `hermes model` | Choose the LLM provider and model. |
| `hermes config set/get/unset` | Edit `config.yaml` from the command line. |
| `hermes mcp install/login/configure` | Install, authenticate, and configure catalog MCP servers. |
| `hermes profile create <name>` | Create an isolated agent profile (and a `<name>` command alias). |
| `hermes -p <name> <command>` | Run any command against a specific profile. |
| `hermes skills list/show` | List and inspect skills. |
| `hermes cron create/list/run` | Create, list, and run scheduled tasks. |
| `hermes kanban create/list/show` | Manage tasks on the multi-agent Kanban board. |
| `hermes gateway start` | Start the messaging/worker gateway. |
| `hermes dashboard` | Launch the web dashboard. |
| `hermes doctor` | Diagnose configuration and connectivity issues. |
| `hermes update` | Update Hermes to the latest version. |

### Hermes dashboard

A built-in web app for administration and monitoring. Start it with `hermes dashboard`; it usually runs at <http://127.0.0.1:9119>.

Features:

- **MCP management:** browse and install catalog entries, and authorize OAuth servers.
- **Session monitoring:** view active and past sessions.
- **Kanban board:** visual view of the multi-agent task board.
- **Skill and profile management:** browse skills and switch between profiles.

### Open WebUI integration

Hermes exposes an OpenAI-compatible API server that [Open WebUI](https://github.com/open-webui/open-webui) can use as a model backend. Tool progress streams to the UI in real time.

1. Enable the API server:

   ```bash
   hermes config set API_SERVER_ENABLED true
   hermes config set API_SERVER_KEY "your-secret-key"
   hermes gateway restart
   ```

2. Run Open WebUI and point it at Hermes:

   ```bash
   docker run -d -p 3000:8080 \
     -e OPENAI_API_BASE_URL=http://host.docker.internal:8642/v1 \
     -e OPENAI_API_KEY=your-secret-key \
     --add-host=host.docker.internal:host-gateway \
     ghcr.io/open-webui/open-webui:main
   ```

3. Open <http://localhost:3000> and select **hermes-agent** from the model list.
