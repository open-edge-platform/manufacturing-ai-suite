# Factory Management Orchestrator

The factory management installer prepares a central [Hermes Agent](https://github.com/NousResearch/hermes-agent) to work with manufacturing applications on remote edge nodes. It uses deployment skills to prepare and deploy applications, exposes each node's MCP server through an SSH tunnel, and registers the servers with Hermes.

This README helps two audiences prepare for and use the installer:

- **Administrator:** prepares the central host and edge nodes, configures the inventory, and runs the setup.
- **Operator:** after setup, asks Hermes to inspect or operate the registered nodes in natural language.

It covers the complete flow from preflight checks through deployment, MCP verification, and day-to-day use.

- [Administrator: prepare and deploy](#administrator-prepare-and-deploy)
- [Operator: access and use Hermes](#operator-access-and-use-hermes)

## What the installer sets up

For each deployment in the inventory, the installer can:

1. Create a Hermes profile configured to run the deployment skill's commands on the node over SSH.
2. Prepare the node and deploy the selected manufacturing application and its MCP server.
3. Establish a local SSH tunnel to the node's MCP endpoint, retrieve and pin its TLS certificate, and register the MCP server with Hermes.

After setup, an operator can start a new Hermes session and ask about the registered nodes. For example:

> Describe node1 and node2, then summarize their status.

The available nodes, skills, prompts, and MCP tools depend on the configured inventory.

## Administrator: prepare and deploy

Complete these steps on the central Hermes host. The administrator owns inventory changes, node preparation, application deployment, MCP registration, and WebUI lifecycle management.

### Prerequisites

#### Central Hermes host

- A Linux host with a normal interactive login session and working **systemd user services**. Run the installer as the Hermes user, not through `sudo` or inside a container. If user services are unavailable, an administrator may need to enable lingering for that user and have them log in again.
- Hermes Agent installed and configured with an LLM provider, as described in [Install Hermes on the central host](#install-hermes-on-the-central-host). The `hermes` command must be available to the user running setup.
- These commands available on the host: `ssh`, `scp`, `ssh-copy-id`, `ssh-keygen`, `curl`, `openssl`, `git`, `base64`, `systemctl`, and `loginctl`.
- Python 3 and PyYAML to read and validate the YAML inventory. On Debian or Ubuntu, install PyYAML with `sudo apt-get install python3-yaml` if it is missing.
- The installer files kept together: `fleet-setup.sh` and `fleet_inventory.py`.
- Network access to the configured Git repositories and to any services used by the skills.

#### Edge nodes

- A supported Intel edge system for the selected application. The included examples expect Intel Panther Lake / Core Ultra 3xx hardware; see the application-specific guide for the current hardware requirements.
- A dedicated deployment account on each node. The account must accept SSH connections from the central host and have a home directory where the application checkout can be created.
- Key-based SSH from the central host. The installer can call `ssh-copy-id` on the first run; have the node account's password available at the terminal if the key is not already installed.
- `make`, `curl`, `git`, Docker Engine, and Docker Compose v2. On apt-based systems, the installer can install missing packages, which requires interactive `sudo` access.
- The deployment account must be able to use Docker. The installer may add it to the `docker` group using `sudo`; membership in this group is root-equivalent, so use a dedicated account and protect its SSH key.
- Outbound network access for the application deployment, including image, package, model, or dependency downloads required by the configured skill. With `source_delivery: node_clone`, nodes also need access to the application Git repository; with `central_copy`, the app source is transferred from the central host.

#### Network and ports

- The central host must be able to connect to each node's configured SSH port (port 22 by default).
- The MCP service is reached on the node's loopback interface through SSH; it does not need to be exposed directly to the network.
- Each deployment needs a unique, available local tunnel port on the central host. The checked-in inventory uses `13001` and `13002`; change them if they are already in use.
- Allow the edge nodes to reach the external registries, repositories, and model/package sources needed for deployment. No inbound public access to the MCP service is required.

### Install Hermes on the central host

Use the [Agent Harness Installer](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/frameworks/agent-harness-install) to install Hermes with a local OpenVINO Model Server (OVMS) backend and Inference Router. Run this on the **central host**, as the user who will run fleet setup, not on the edge nodes.

Obtain the installer in a separate checkout:

```bash
git clone https://github.com/open-edge-platform/edge-ai-libraries.git
cd edge-ai-libraries/frameworks/agent-harness-install
```

Review the installer and its [get-started prerequisites](https://github.com/open-edge-platform/edge-ai-libraries/blob/main/frameworks/agent-harness-install/docs/user-guide/get-started.md) before running it. For a reproducible deployment, use your site's reviewed repository revision. The GPU path requires a supported Intel GPU with its driver and compute runtime already provisioned; allow sufficient memory and disk space for the selected model and container images.

Install Hermes using the selected OVMS image and model:

```bash
HARNESS_OVMS_IMAGE=openvino/model_server:2026.4.1-gpu \
./install.sh --harness hermes --model OpenVINO/Qwen3.6-35B-A3B-int4-ov --model-hub huggingface
```

The harness installer prepares host dependencies, starts OVMS and the Inference Router, downloads the model, and installs Hermes. The `huggingface` hub downloads the published model without converting it; it can be served only if the downloaded repository includes the OVMS `graph.pbtxt` configuration. Check the install output for successful model registration, not just a completed download. Supply any required model access credentials through environment variables, never in the command or inventory.

Configure any required proxy in the installer environment before running it. Its startup step may configure Docker's daemon proxy and restart Docker when those settings change; schedule this on a host where a restart will not interrupt other workloads.

**Temporary model choice:** the Hermes -> Inference Router -> OVMS configuration currently has known integration issues and still requires full end-to-end validation. The installation command above provisions the local backend, but does not establish that Hermes can successfully use it. For now, select the `nous` provider and `upstage/solar-mini4:free` model during Hermes onboarding rather than configuring Hermes to use the local router endpoint.

The harness installer prints the Inference Router endpoint and configuration guidance, but does not automatically configure and smoke-test Hermes. After installation, run:

```bash
hermes setup model
```

In the provider/model selection flow:

1. Choose the Nous provider (`nous`).
2. Complete the provider's authentication flow if prompted.
3. Select `upstage/solar-mini4:free` as the default model. Use the full model identifier, including the `upstage/` prefix.

These selections match the provider and default model in the current central-host Hermes configuration. After setup, confirm that the `model` section in `~/.hermes/config.yaml` contains:

```yaml
model:
  provider: nous
  default: upstage/solar-mini4:free
```

This is only the relevant configuration fragment, not a replacement for the complete file. Preserve all other settings. If the provider or model is unavailable to your account, stop and confirm an approved alternative with the administrator rather than assuming the local backend is ready. Keep credentials out of commands, the inventory, and chat.

This temporary choice does not validate the local inference path. If the selected provider is hosted externally, prompts and tool results may leave the central host; use it only with data approved for that provider.

Start a test chat to confirm the selected model responds:

```bash
hermes
```

Ask a simple question and verify that it receives a response. Only then return to this repository's `factory-management-orchestrator` directory and continue with node preparation and fleet deployment.

When the integration issues are resolved, configure Hermes with the Inference Router's OpenAI-compatible endpoint and served model reported by the installer, not the OVMS endpoint directly. Keep the local backend bound to loopback and validate both inference and the fleet's MCP tool calls before replacing the temporary model configuration.

### Set the factory-management persona

[`SOUL.md`](SOUL.md) is a reusable Hermes persona template for this orchestrator. It defines the assistant's purpose, evidence-based reporting, administrator/operator workflows, and confirmation boundaries for operational changes. It deliberately contains no node addresses, credentials, or fixed model selections; those remain in inventory, provider configuration, and live tool results.

Review the template before applying it. From this directory, as the central Hermes user:

```bash
hermes_home="${HERMES_HOME:-$HOME/.hermes}"
install -d -m 0700 "$hermes_home"
if [ -f "$hermes_home/SOUL.md" ]; then
  cp -i "$hermes_home/SOUL.md" "$hermes_home/SOUL.md.backup"
fi
cp -i ./SOUL.md "$hermes_home/SOUL.md"
chmod 600 "$hermes_home/SOUL.md"
```

The copy commands prompt before overwriting existing files. If the active persona contains customizations you need, merge the reviewed template into it instead of replacing it. Keep the backup until you have verified the new behavior.

Start a new default-profile Hermes chat, including in the WebUI, and ask it to explain its factory-management role and how it handles a request to stop a pipeline. Confirm that it identifies the target and seeks approval rather than making a change. Review any profile-specific persona separately; these instructions do not install the template into node profiles.

This is behavioral guidance, not an access-control mechanism. The fleet installer does not automatically install or overwrite the persona, and changing this template alone does not change an existing Hermes installation.

### Prepare each edge node

Run the following on each edge node from an existing administrator account, not on the central Hermes host.

#### Create or reuse the deployment account

Check whether the account already exists:

```bash
id deploy
```

If it does not exist, create it:

```bash
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy
```

Set the password interactively; do not put it in a script or chat. Reuse an existing deployment account rather than deleting and recreating it, which would remove its home directory, keys, configuration, and application data.

Once Docker is installed and its `docker` group exists, grant the account Docker access:

```bash
sudo usermod -aG docker deploy
```

If the installer must install packages or change group membership, arrange the required `sudo` permissions under your site's policy. On Ubuntu/Debian, an administrator can grant temporary membership in the `sudo` group:

```bash
sudo usermod -aG sudo deploy
```

This grants broad administrative access, so prefer having an administrator preinstall packages and configure Docker access where possible. Remove temporary sudo access after preparation if it is no longer needed. Docker group membership itself remains root-equivalent.

Open a fresh login session so the new group memberships take effect:

```bash
sudo -iu deploy
id
docker info
docker compose version
```

Use a login session rather than `su deploy`, which can retain the previous user's working directory and environment. Return to the administrator session with `exit` when finished. The fleet installer itself still runs on the central host.

Do not kill all processes belonging to `deploy`, delete the account, or remove all Docker containers and images as part of routine preparation. These actions can interrupt unrelated workloads and destroy data. Any reset must be separately planned, backed up, and limited to the intended deployment resources.

#### Configure a proxy only if required

Skip this section on networks with direct outbound access. Replace `proxy.example.invalid` and the example port `8080` below with your site's approved proxy hostname and port.

For commands in the deployment user's current shell, set:

```bash
export HTTP_PROXY="http://proxy.example.invalid:8080"
export HTTPS_PROXY="$HTTP_PROXY"
export NO_PROXY="127.0.0.1,localhost,::1"
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export no_proxy="$NO_PROXY"
```

Add node hostnames and internal service destinations to `NO_PROXY` as required by your network. These exports apply only to this shell and its child processes: later SSH sessions, Hermes commands, `sudo`, system services, and containers do not automatically inherit them. Configure the appropriate environment for each context that requires the proxy. Do not embed proxy credentials in committed files or chats.

For new containers and Docker build arguments, configure the Docker client as `deploy`:

```bash
install -d -m 0700 "$HOME/.docker"
```

Create or edit `$HOME/.docker/config.json` to include the following `proxies` object. If the file already exists, merge this object into it rather than overwriting registry credentials, credential-helper settings, or other configuration:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.example.invalid:8080",
      "httpsProxy": "http://proxy.example.invalid:8080",
      "noProxy": "127.0.0.1,localhost,::1"
    }
  }
}
```

After saving, restrict access to the file:

```bash
chmod 600 "$HOME/.docker/config.json"
```

This Docker client configuration affects new containers and builds; it does **not** configure the Docker daemon's image pulls, existing containers, host package managers, or Git. If image pulls require a proxy, have the node administrator configure the Docker daemon's proxy separately and schedule any daemon restart to avoid disrupting running workloads. Host package installation may also need its own proxy configuration.

### Prepare the inventory

Edit [`hosts.yaml`](hosts.yaml) before deploying:

1. Replace `node1.example.invalid` and `node2.example.invalid` with the real addresses of your edge nodes. These `.invalid` names are placeholders, not usable hosts.
2. Confirm the deployment user, SSH port, and private-key path under `defaults`. Override a value for an individual node only when it differs.
3. Keep each deployment `name` stable and unique. It identifies the Hermes profile and MCP server.
4. Assign a unique `local_port` to every deployment.
5. Review the recipe's repository, branch, application directory, skill, prompt, environment updates, and MCP certificate settings.

Do not put passwords, tokens, or other secrets in the inventory. The installer creates missing application credentials and transfers them using files over SSH. It prompts for an SSH password only if it needs to install a key.

The normal recipe deployment removes and recreates its managed checkout. Back up any local files or manually supplied credentials in that checkout before redeploying. `--no-deploy` prepares nodes and profiles and connects to an application that is already running, without deleting or redeploying its checkout.

### Preflight validation

From this directory, print and validate the planned deployments without connecting to nodes or changing anything:

```bash
./fleet-setup.sh --list
```

Check the displayed node names, recipes, profiles, hosts, local ports, and skills. Update the inventory and repeat the check if any value is wrong. If you use a different inventory file, pass it explicitly:

```bash
./fleet-setup.sh --hosts /path/to/hosts.yaml --list
```

### Run the installer

Run the installer from this directory in an interactive terminal, as the same user who installed and configured Hermes:

```bash
bash ./fleet-setup.sh
```

The installer uses `hosts.yaml` by default. It validates the inventory, checks the central host, and then prepares each configured deployment. Depending on the node's state, it may:

- Create or use the configured SSH key and use `ssh-copy-id` to install the public key on a node. If needed, enter the node account's password in the terminal; never enter it in a Hermes chat.
- Install missing node packages on apt-based distributions and add the deployment account to the Docker group. These steps may prompt for `sudo`.
- Fetch and install the configured deployment skill, prepare the app checkout and environment, and run the recipe's deployment prompt and smoke check.
- Establish a user-level SSH tunnel, retrieve and pin the MCP TLS certificate, register the server and allowed tools with Hermes, and test the connection.

Keep the terminal open to answer SSH, `sudo`, or approval prompts. The installer reports progress and prints a connection summary when it finishes. If a step fails, read the error and stage output before retrying.

To use another inventory, pass its path:

```bash
bash ./fleet-setup.sh --hosts /path/to/hosts.yaml
```

To work through a single deployment with an interactive Hermes session, select its node. The following uses `node1`, which has one deployment in the checked-in inventory:

```bash
bash ./fleet-setup.sh --node node1 --interactive
```

If a node has multiple deployments, also pass `--recipe` with the recipe identifier from your inventory to select a single assignment.

Other useful options:

| Option | Purpose |
| --- | --- |
| `--list` | Validate and display the planned deployments without connecting to nodes or changing anything |
| `--node NAME` | Select a node; repeatable for multiple nodes |
| `--recipe NAME` | Select a recipe; repeatable for multiple recipes |
| `--no-deploy` | Prepare nodes and profiles and connect to an app that is already deployed, without redeploying it |
| `--user NAME` | Set the default SSH user where the inventory does not specify one |
| `--skip-platform-check` | Skip the hardware check for CI or validation only; do not use this to bypass production hardware requirements |

Node and recipe selectors can be repeated. If none are provided, the installer processes every assignment in the inventory.

### Verify MCP registration

When the installer finishes, check each registered server from the central host. Use the deployment `name` from the inventory:

```bash
hermes mcp test node1
hermes mcp test node2
```

If Hermes was already running, start a new session or reload its MCP servers with `/reload-mcp`. You can also check the tools in a one-shot chat:

```bash
hermes chat --oneshot -q \
  "Call mcp__node1__describe and mcp__node2__describe and summarize each result."
```

The tunnel and MCP server must be available for the test to pass. The installer pins the retrieved TLS certificate; do not disable certificate verification to work around a TLS error. If the app is already running with a regenerated certificate, use `bash ./fleet-setup.sh --no-deploy` to refresh the pin and registration without redeploying the app. This still performs node and profile preparation; it is not a read-only check.

### Bring up Hermes WebUI

The optional community Hermes WebUI provides browser-based chat using the local Hermes installation. It is third-party software, not a separate fleet deployment service. Run [`hermes-webui.sh`](hermes-webui.sh) on the central host as the same user who configured Hermes and registered the MCP servers.

Before starting, ensure that:

- `git`, Python 3, and `curl` are available, with network access to the WebUI Git repository.
- Hermes is configured and its configuration file exists at `~/.hermes/config.yaml` (or under the configured `HERMES_HOME`).
- Local port `8787` is available.

From this directory, run:

```bash
bash ./hermes-webui.sh start
```

On the first run, the script clones the WebUI into `~/hermes-webui`, checks out the pinned release `v0.52.492`, and asks you to choose and repeat a password. The password must be at least 12 characters and cannot contain quotes. Run this interactively to set the password yourself; without a terminal, the script generates one instead.

The script stores the WebUI settings in `~/hermes-webui/.env` with mode `600`, starts the daemon, and checks its `/health` endpoint. Wait for the message that the WebUI is up before handing access to the operator.

The default address is <http://127.0.0.1:8787/>. Keep password login enabled and prefer loopback with SSH forwarding for remote access. For an existing installation previously bound to another address, restore loopback explicitly:

```bash
HERMES_WEBUI_HOST=127.0.0.1 bash ./hermes-webui.sh restart
```

For direct access from a remote system on a trusted network, set `HERMES_WEBUI_HOST` to an IPv4 address assigned to the central host, or use `0.0.0.0` to listen on all IPv4 interfaces:

```bash
# Alternatively, replace 0.0.0.0 with the central host's own IPv4 address.
HERMES_WEBUI_HOST=0.0.0.0 bash ./hermes-webui.sh restart
```

Open `http://<central-host-ip>:8787/` from the remote system; `0.0.0.0` is a bind wildcard, not a browser destination. The script saves the bind address for subsequent starts. Restrict access to authorized clients with a firewall and prefer SSH forwarding or a TLS reverse proxy: direct HTTP sends passwords and chat content unencrypted.

Use these commands to manage it:

```bash
bash ./hermes-webui.sh status
bash ./hermes-webui.sh logs
bash ./hermes-webui.sh restart
bash ./hermes-webui.sh stop
```

`start` installs only if needed; `install` installs or updates to the configured pinned release but does not start the service. The script also accepts `HERMES_WEBUI_DIR`, `HERMES_WEBUI_VERSION`, and `HERMES_WEBUI_PORT` overrides. Use a reviewed stable release tag, and adjust the browser URL and SSH forwarding ports if you change the port.

**Access warning:** the WebUI includes terminal and file access with the central Hermes user's permissions. The administrator/operator personas in this README describe responsibilities, not enforced access-control roles. Grant access only to trusted operators; do not treat a profile selection as a security boundary. Do not expose the plain-HTTP service directly to an untrusted network.

### Redeployment and credential handling

- **Recipe deployments replace their managed checkout.** Local `.env` values, downloaded models, and edits inside that checkout can be deleted during a normal deployment. Back up anything that must be retained and be ready to restore manually supplied secrets.
- **Use `--no-deploy` when the app is already running** and you need to prepare the Hermes connection without redeployment. It preserves the managed checkout, but still performs node and profile preparation and MCP registration.
- **Keep secrets out of `hosts.yaml` and chat.** The inventory contains variable names and configuration, not credential values. The installer generates missing app credentials and transfers them over SSH; MCP credentials are stored on the central host with restricted permissions.
- **Treat Docker access as privileged.** Membership in the node's `docker` group is root-equivalent. Use a dedicated deployment account and protect its SSH key.

## Operator: access and use Hermes

Begin after the administrator has deployed the applications, verified MCP registration, and provided approved access to Hermes. Operators do not need to rerun the installer for normal queries.

### Open the WebUI

On the central host, open <http://127.0.0.1:8787/> and log in with the WebUI password supplied securely by the administrator.

Keep that SSH session open, then visit <http://127.0.0.1:8787/> on your workstation. If local port `8787` is occupied, use a different local port, for example `-L 8788:127.0.0.1:8787`, and open <http://127.0.0.1:8788/> instead. This browser-access tunnel is separate from the administrator-managed MCP tunnels to the edge nodes.

### Choose the right profile

- Select **`default`** for fleet queries through the registered MCP tools. In the checked-in inventory, the MCP servers are named `node1` and `node2`.
- Node profiles such as **`node1`** and **`node2`** run terminal commands on their corresponding edge nodes over SSH. Use these only for administrator-approved node-specific work; they are not required for normal MCP queries.

Start a new chat after MCP registrations change. In a CLI chat, `/reload-mcp` can reload the registrations. The central host's MCP tunnels and the remote applications must remain running while you use their tools.

### Use natural-language requests

After registration, operators use the default Hermes profile and address servers by their inventory deployment name. For example:

> Describe node1 and node2, then compare their current status.

Before requesting a processing change, ask Hermes to describe the selected application's pipeline controls and required options:

> Describe the pipeline controls available on node1 and the options needed to start processing. Do not start it yet.

Or query recent data:

> Show the latest 10 insights from node1 and summarize the results, including the time range.

Starting or stopping a live pipeline changes processing. Review the requested action and confirm it is intended before authorizing it. The available tools and accepted options depend on the recipe configured for that deployment.

### Use the CLI instead of the WebUI

If authorized to use the central Hermes account, start a chat from the central host:

```bash
hermes
```

Use the same natural-language requests as in the browser. If tools are missing, a tunnel is unavailable, or authentication fails, report the affected server and error to the administrator. Do not paste passwords, tokens, or private keys into chat.

## Related files

- [`SOUL.md`](SOUL.md) — reusable factory-management persona for the central Hermes assistant.
- [`fleet-setup.sh`](fleet-setup.sh) — installer entry point.
- [`fleet_inventory.py`](fleet_inventory.py) — recipe inventory validation and orchestration.
- [`hermes-webui.sh`](hermes-webui.sh) — optional Hermes WebUI installer.
