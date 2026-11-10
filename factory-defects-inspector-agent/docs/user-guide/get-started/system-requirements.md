# System Requirements

Make sure that each system meets these requirements before you start.

## Central Hermes Host

- A Linux host with an interactive login session and working systemd user services.
- Run the installer as the Hermes user. Do not use `sudo` or a container.
- If user services are not available, ask an administrator to enable lingering for that user. Then log in again.
- Hermes Agent, installed and configured with an LLM provider. See [Install Hermes, Set the Persona, and Bring Up the WebUI](./set-up-central-host.md).
- The `hermes` command, available to the user who runs the setup.
- These commands: `ssh`, `scp`, `ssh-copy-id`, `ssh-keygen`, `curl`, `openssl`, `git`, `base64`, `systemctl`, and `loginctl`.
- Python 3 and PyYAML. On Debian or Ubuntu, run `sudo apt-get install python3-yaml` if PyYAML is not installed.
- The files `fleet-setup.sh` and `fleet_inventory.py` in the same directory.
- Network access to the configured Git repositories and to the services that the skills use.

## Edge Nodes

- A supported Intel edge system for the selected application. The examples need
  Intel® Core™ Ultra Series 3 (Panther Lake) or Core Ultra 3xx hardware.
  See the guide for the application for the current requirements.
- A dedicated deployment account on each node. The account must accept SSH connections from the central host. It must have a home directory for the application checkout.
- Key-based SSH from the central host. If the key is not installed, the installer runs `ssh-copy-id`. Keep the password of the node account ready.
- `make`, `curl`, `git`, Docker Engine, and Docker Compose v2. On apt-based systems, the installer can install missing packages. This needs interactive `sudo` access.
- Docker access for the deployment account. The installer can add the account to the `docker` group with `sudo`.
- Outbound network access to download images, packages, and models.
- With `source_delivery: node_clone`, access to the application Git repository. With `source_delivery: central_copy`, the central host sends the source to the node.

> [!CAUTION]
> Use a dedicated deployment account and protect its SSH key. Membership in the `docker` group
> gives root-equivalent access.

## Network and Ports

- The central host connects to the SSH port of each node. The default is port 22.
- The Model Context Protocol (MCP) service listens on the loopback interface of the node.
  The central host reaches it through SSH. Do not expose it to the network.
- Each deployment needs a unique local tunnel port on the central host. The checked-in inventory uses `13001` and `13002`. Change them if they are in use.
- The nodes need access to the external registries, repositories, and model sources. No inbound public access is necessary.
