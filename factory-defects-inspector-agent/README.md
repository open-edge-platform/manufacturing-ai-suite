# Factory Defects Inspector Agent

The Factory Defects Inspector Agent is a [Hermes Agent](https://github.com/NousResearch/hermes-agent) on a central host that helps people investigate defects and anomalies reported by manufacturing applications on remote edge nodes. The installer (`fleet-setup.sh`) deploys the applications, exposes each node's MCP server through an SSH tunnel, and registers the servers with Hermes.

## Documentation

The full documentation is in [docs/user-guide](./docs/user-guide/index.md):

- [Overview](./docs/user-guide/index.md): What the agent and the installer do, and who the guides are for.
- [How It Works](./docs/user-guide/how-it-works.md): High-level admin/operator flows and the deployment and MCP-registration architecture.
- [Get Started](./docs/user-guide/get-started.md) (administrator):
  - [System Requirements](./docs/user-guide/get-started/system-requirements.md)
  - [Install Hermes, Set the Persona, and Bring Up the WebUI](./docs/user-guide/get-started/install-hermes.md)
  - [Prepare the Edge Nodes](./docs/user-guide/get-started/prepare-edge-nodes.md)
  - [Configure the Inventory and Deploy](./docs/user-guide/get-started/deploy-the-fleet.md)
- [How-to Guides](./docs/user-guide/how-to-guides.md):
  - [Use Hermes as an Operator](./docs/user-guide/how-to-guides/use-hermes.md)
  - [Redeploy and Handle Credentials](./docs/user-guide/how-to-guides/redeploy-and-handle-credentials.md)

## Related files

- [`SOUL.md`](SOUL.md) — reusable Factory Defects Inspector Agent persona for the central Hermes assistant.
- [`fleet-setup.sh`](fleet-setup.sh) — installer entry point.
- [`fleet_inventory.py`](fleet_inventory.py) — recipe inventory validation and deployment planning.
- [`agents/hermes.sh`](agents/hermes.sh) — Hermes agent-harness adapter (selected via `HARNESS_AGENT`; documents the adapter contract for other harnesses).
- [`hermes-webui.sh`](hermes-webui.sh) — optional Hermes WebUI installer and `SOUL.md` persona setup (`setup`/`persona` commands).
