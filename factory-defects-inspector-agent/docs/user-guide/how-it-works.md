# How It Works

This page gives a high-level view of the Factory Defects Inspector Agent: who does what, and how the central host, the edge nodes, and the MCP connections fit together. For step-by-step instructions, start with [Get Started](./get-started.md).

## Administrator and operator flows

The administrator sets the system up once per fleet change; operators then use it through chat without touching the installer.

![Administrator and operator flows](./_assets/fdi-admin-operator-flows.drawio.svg)

- **Administrator:** installs the agent harness (Hermes with a local Inference Router → OVMS backend), sets the model and the `SOUL.md` persona, describes nodes and recipes in `hosts.yaml`, and runs `./fleet-setup.sh`. The installer prepares the nodes, deploys the applications with their MCP servers, and registers each server with the central agent. After `hermes mcp test` passes, the administrator hands the WebUI password (or CLI access) to operators.
- **Operator:** opens the WebUI or CLI on the default profile and asks questions in natural language. The agent answers through the registered MCP tools and asks for confirmation before any pipeline change.

## Deployment and MCP registration

One central host runs the agent and its local LLM backend; each edge node runs a manufacturing application with its own MCP server. Nothing on the nodes is exposed directly — all access flows through SSH.

![Central host and edge node deployment](./_assets/fdi-deployment-architecture.drawio.svg)

- **Deploy:** `fleet-setup.sh` (through the `agents/<HARNESS_AGENT>.sh` adapter) creates one agent profile per node, cloned from the default profile, with an SSH terminal pointed at that node, the deployment skill, and an approval policy. The agentic deployment then builds and starts the application and its MCP server on the node over SSH.
- **Connect:** the installer starts a persistent `fleet-tunnel@` systemd unit per node, forwarding a local port (for example `localhost:13001`) to the node's TLS-protected MCP endpoint (`:3000`), pins the server certificate, and registers the tunneled URL, credentials reference, and tool allow-list with the central agent.
- **Operate:** operator questions in the default profile become MCP tool calls that travel through the SSH tunnels to the node applications; inference stays on the central host's local LLM backend (or the configured provider).
