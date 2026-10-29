# Configure the Inventory and Deploy

## Prepare the inventory

Edit `hosts.yaml` before deploying:

1. Replace `node1.example.invalid` and `node2.example.invalid` with the real addresses of your edge nodes. These `.invalid` names are placeholders, not usable hosts.
2. Confirm the deployment user, SSH port, and private-key path under `defaults`. Override a value for an individual node only when it differs.
3. Keep each deployment `name` stable and unique. It identifies the Hermes profile and MCP server.
4. Assign a unique `local_port` to every deployment.
5. Review the recipe's repository, branch, application directory, skill, prompt, environment updates, and MCP certificate settings.

Do not put passwords, tokens, or other secrets in the inventory. The installer creates missing application credentials and transfers them using files over SSH. It prompts for an SSH password only if it needs to install a key.

The normal recipe deployment removes and recreates its managed checkout. Back up any local files or manually supplied credentials in that checkout before redeploying. `--no-deploy` prepares nodes and profiles and connects to an application that is already running, without deleting or redeploying its checkout. Profile preparation recreates each node profile as a clone of the current default profile on every run, so configure the central model/provider settings and install the `SOUL.md` persona (see [Install Hermes](install-hermes.md)) before running the installer — node profiles inherit the default profile's configuration and persona at creation time. Node chat history in those profiles is not preserved across runs.

## Preflight validation

From the `factory-defects-inspector-agent` directory, print and validate the planned deployments without connecting to nodes or changing anything:

```bash
./fleet-setup.sh --list
```

Check the displayed node names, recipes, profiles, hosts, local ports, and skills. Update the inventory and repeat the check if any value is wrong. If you use a different inventory file, pass it explicitly:

```bash
./fleet-setup.sh --hosts /path/to/hosts.yaml --list
```

## Run the installer

Run the installer from the `factory-defects-inspector-agent` directory in an interactive terminal, as the same user who installed and configured Hermes:

```bash
./fleet-setup.sh
```

The installer uses `hosts.yaml` by default. It validates the inventory, checks the central host, and then prepares each configured deployment. Depending on the node's state, it may:

- Create or use the configured SSH key and use `ssh-copy-id` to install the public key on a node. If needed, enter the node account's password in the terminal; never enter it in a Hermes chat.
- Install missing node packages on apt-based distributions and add the deployment account to the Docker group. These steps may prompt for `sudo`.
- Fetch and install the configured deployment skill, prepare the app checkout and environment, and run the recipe's deployment prompt and smoke check.
- Establish a user-level SSH tunnel, retrieve and pin the MCP TLS certificate, register the server and allowed tools with Hermes, and test the connection.

Keep the terminal open to answer SSH, `sudo`, or approval prompts. The installer reports progress and prints a connection summary when it finishes. If a step fails, read the error and stage output before retrying.

To use another inventory, pass its path:

```bash
./fleet-setup.sh --hosts /path/to/hosts.yaml
```

To work through a single deployment with an interactive Hermes session, select its node. The following uses `node1`, which has one deployment in the checked-in inventory:

```bash
./fleet-setup.sh --node node1 --interactive
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

The agent-specific steps (per-node profiles, skills, deploy chats, and MCP registration) run through an adapter selected by the `HARNESS_AGENT` environment variable (`agents/<name>.sh` next to the installer). Hermes (`hermes`, the default) is the only adapter provided today; the adapter contract is documented in `agents/hermes.sh` for anyone adding support for another agent harness. Agentic deployment requires an adapter that declares the `deploy` capability; an adapter without it (any MCP-capable harness with only the baseline functions) can still run the `--no-deploy` flow — node preparation, tunnels, and MCP registration for an already-deployed fleet.

## Verify MCP registration

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

The tunnel and MCP server must be available for the test to pass. The installer pins the retrieved TLS certificate; do not disable certificate verification to work around a TLS error. If the app is already running with a regenerated certificate, use `./fleet-setup.sh --no-deploy` to refresh the pin and registration without redeploying the app. This still performs node and profile preparation; it is not a read-only check.
