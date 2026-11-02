# How It Works

This page gives a high-level view of the Factory Defects Inspector Agent: who does what, and how the central host, the edge nodes, and the MCP connections fit together. For step-by-step instructions, start with [Get Started](./get-started.md).

## Administrator and operator flows

The administrator sets the system up once per fleet change; operators then use it through chat without touching the installer.

![Administrator and operator flows](./_assets/fdi-admin-operator-flows.drawio.svg)

- **Administrator:** installs the agent harness (Hermes with a local Inference Router → OVMS backend), sets the model and the `SOUL.md` persona, prepares each edge node's deployment account and Docker access, describes nodes and recipes in `hosts.yaml`, and runs `./fleet-setup.sh`. The installer prepares the nodes, deploys the applications with their MCP servers, and registers each server with the central agent. After `hermes mcp test` passes, the administrator hands the WebUI password (or CLI access) to operators. To deploy an application without the agent, the administrator instead runs `--prepare-only`, deploys the application on the node, and runs `--no-deploy` (the dashed box in the diagram).
- **Operator:** opens the WebUI or CLI on the default profile and asks questions in natural language. The agent answers through the registered MCP tools and asks for confirmation before any pipeline change.

## Full run: prepare, deploy, and connect

One central host runs the agent and its LLM backend; each edge node runs a manufacturing application with its own MCP server. The node applications are not exposed to the network directly — the installer reaches each node over SSH, and the agent reaches each MCP server through an SSH tunnel.

![Central host and edge node deployment](./_assets/fdi-deployment-architecture.drawio.svg)

This diagram shows `./fleet-setup.sh` without options. The numbered arrows show the order: 1–2 provision, 3–5 deploy, 6 connect, 7–8 operate. Arrows are color-coded: dashed gray for one-time provisioning, blue for SSH preparation and deployment, orange for the SSH tunnels to the node MCP servers, and black for commands, chat, and tool calls.

- **Provision (steps 1–2, one-time):** the administrator runs the [Agent Harness Installer](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/frameworks/agent-harness-install), which sets up the central host — Hermes, the Inference Router, and OVMS — as described in [Install Hermes, Set the Persona, and Bring Up the WebUI](./get-started/install-hermes.md). The installer only provisions; it takes no part in later deployments or chats.
- **Deploy (steps 3–5):** the administrator runs `fleet-setup.sh` (step 3), which creates one agent profile per node (step 4), cloned from the default profile, with an SSH terminal pointed at that node, the deployment skill, and an approval policy. Over SSH (step 5), `fleet-setup.sh` prepares each node (packages, application checkout, generated credentials), and the node profiles then run the agentic deployment that builds and starts the application and its MCP server.
- **Connect (step 6):** for each node, the installer starts a persistent `fleet-tunnel@` systemd unit that opens an SSH tunnel from a local port (for example `localhost:13001` for node 1 and `localhost:13002` for node 2) to the node's loopback MCP endpoint (`127.0.0.1:3000`, nginx with TLS). It then pins the server certificate and registers the tunneled URL, a credentials reference, and the tool allow-list with the default profile (the "registers MCP servers" arrow).
- **Operate (steps 7–8):** operators chat with the default profile through the WebUI or the CLI (step 7). Their questions become MCP tool calls that travel through the SSH tunnels to the node applications (step 8). Inference uses the central host's local LLM backend (`OpenVINO/Qwen3.5-9B-int8-ov` served by OVMS through the Inference Router), configured in the default profile as described in the get-started guide.

## Connect applications that are already running

Use `--no-deploy` when the application already runs on the node. The installer then connects the MCP server only. It does not prepare or deploy anything.

![Central host and edge nodes with applications that already run](./_assets/fdi-no-deploy-architecture.drawio.svg)

The numbered arrows show the order: 1 run, 2–5 reach the node over SSH, 6 register and test, 7–8 operate. The colors have the same meaning as in the full run.

1. **Run:** the administrator runs `./fleet-setup.sh --no-deploy`.
2. **Check SSH access:** the installer connects to each node. It installs the public key if the node does not have it.
3. **Read the MCP credentials:** the installer reads them from the `.env` file of the application on the node. It stores them in the credential store of the agent.
4. **Start the tunnels:** the installer starts one `fleet-tunnel@` unit for each node. Each unit opens an SSH tunnel to the MCP server of the node.
5. **Pin the certificate:** the installer fetches the TLS certificate of the MCP server and pins it.
6. **Register and test:** the installer registers each MCP server with the default profile and tests the connection.
7. **Operate:** operators chat with the default profile (step 7). Their questions become MCP tool calls through the tunnels (step 8), as in the full run.

If the `.env` file has no credentials, the installer uses the credentials that it already stored. In a terminal, it can ask for them. The installer does not install packages, copy source code, change the `.env` file, create node profiles, or touch the running containers. It does restart the tunnels and replace the registration, so it is not a read-only command.

To deploy an application yourself, run `--prepare-only` first. Deploy the application on the node, and then run `--no-deploy`. For the commands, see [Connect applications that are already running](./get-started/deploy-the-fleet.md#connect-applications-that-are-already-running).
