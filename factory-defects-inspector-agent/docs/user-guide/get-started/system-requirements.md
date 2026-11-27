# System Requirements

This page provides detailed hardware, software, and platform requirements to help you set up and run the Factory Defects Inspector Agent efficiently. Make sure that each system meets these requirements before you start.

The deployment has two kinds of systems:

- The **central Hermes host** runs the agent and the local model.
- The **edge nodes** run the manufacturing applications that the agent investigates.

## Minimum Requirements

| Component     | Central Hermes host                         | Edge node                        |
|---------------|---------------------------------------------|----------------------------------|
| **Processor** | Intel® Core™ Ultra Processors (Series 3, 2) | See the application links below. |
| **RAM**       | Minimum 32 GB                               | See the application links below. |
| **Storage**   | Minimum 64 GB (128 GB recommended)          | See the application links below. |

The edge node requirements depend on the application that you deploy:

- [Industrial Edge Insights Multimodal](https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/industrial-edge-insights-multimodal/docs/user-guide/get-started/system-requirements.md). The checked-in `weld` recipe deploys the agentic variant; follow its [minimum system requirements](https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/industrial-edge-insights-multimodal/docs/user-guide/how-to-guides/how-to-deploy-agent-workflow.md#minimum-system-requirements): Intel® Core™ Ultra Series 3 or newer, at least 48 GB RAM, and 512 GB storage.
- [Industrial Edge Insights Time Series](https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/industrial-edge-insights-time-series/docs/user-guide/get-started/system-requirements.md)

## Software Requirements

### Central Hermes host

**Required Software**:

- A Linux host with an interactive login session and working systemd user services.
- Hermes Agent, installed and configured with an LLM provider. See [Install Hermes, Set the Persona, and Bring Up the WebUI](./set-up-central-host.md).
- The `hermes` command, available to the user who runs the setup.
- These commands: `ssh`, `scp`, `ssh-copy-id`, `ssh-keygen`, `curl`, `openssl`, `git`, `base64`, `systemctl`, and `loginctl`.
- Python 3 and PyYAML. On Debian or Ubuntu, run `sudo apt-get install python3-yaml` if PyYAML is not installed.
- The files `fleet-setup.sh` and `fleet_inventory.py` in the same directory.

**Account requirements**:

- Run the installer as the Hermes user. Do not use `sudo` or a container.
- If user services are not available, ask an administrator to enable lingering for that user. Then log in again.

### Edge nodes

**Required Software**:

- `make`, `curl`, `git`, Docker Engine, and Docker Compose v2. On apt-based systems, the installer can install missing packages. This needs interactive `sudo` access.
- Docker access for the deployment account. The installer can add the account to the `docker` group with `sudo`.

**Account and access requirements**:

- A dedicated deployment account on each node. The account must accept SSH connections from the central host. It must have a home directory for the application checkout.
- Key-based SSH from the central host. If the key is not installed, the installer runs `ssh-copy-id`. Keep the password of the node account ready.
- With `source_delivery: node_clone`, access to the application Git repository. With `source_delivery: central_copy`, the central host sends the source to the node.

> [!CAUTION]
> Use a dedicated deployment account and protect its SSH key. Membership in the `docker` group
> gives root-equivalent access.

## Network and Ports

- Network access from the central host to the configured Git repositories and to the services that the skills use.
- The central host connects to the SSH port of each node. The default is port 22.
- The Model Context Protocol (MCP) service listens on the loopback interface of the node.
  The central host reaches it through SSH. Do not expose it to the network.
- Each deployment needs a unique local tunnel port on the central host. The checked-in inventory uses `13001` and `13002`. Change them if they are in use.
- The nodes need access to the external registries, repositories, and model sources. No inbound public access is necessary.

## Validation

Ensure all required software is installed and configured before proceeding to [Get Started](../get-started.md).
