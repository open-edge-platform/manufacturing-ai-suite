# System Requirements

## Central Hermes host

- A Linux host with a normal interactive login session and working **systemd user services**. Run the installer as the Hermes user, not through `sudo` or inside a container. If user services are unavailable, an administrator may need to enable lingering for that user and have them log in again.
- Hermes Agent installed and configured with an LLM provider, as described in [Install Hermes on the central host](./install-hermes.md). The `hermes` command must be available to the user running setup.
- These commands available on the host: `ssh`, `scp`, `ssh-copy-id`, `ssh-keygen`, `curl`, `openssl`, `git`, `base64`, `systemctl`, and `loginctl`.
- Python 3 and PyYAML to read and validate the YAML inventory. On Debian or Ubuntu, install PyYAML with `sudo apt-get install python3-yaml` if it is missing.
- The installer files kept together: `fleet-setup.sh` and `fleet_inventory.py`.
- Network access to the configured Git repositories and to any services used by the skills.

## Edge nodes

- A supported Intel edge system for the selected application. The included examples expect Intel Panther Lake / Core Ultra 3xx hardware; see the application-specific guide for the current hardware requirements.
- A dedicated deployment account on each node. The account must accept SSH connections from the central host and have a home directory where the application checkout can be created.
- Key-based SSH from the central host. The installer can call `ssh-copy-id` on the first run; have the node account's password available at the terminal if the key is not already installed.
- `make`, `curl`, `git`, Docker Engine, and Docker Compose v2. On apt-based systems, the installer can install missing packages, which requires interactive `sudo` access.
- The deployment account must be able to use Docker. The installer may add it to the `docker` group using `sudo`; membership in this group is root-equivalent, so use a dedicated account and protect its SSH key.
- Outbound network access for the application deployment, including image, package, model, or dependency downloads required by the configured skill. With `source_delivery: node_clone`, nodes also need access to the application Git repository; with `central_copy`, the app source is transferred from the central host.

## Network and ports

- The central host must be able to connect to each node's configured SSH port (port 22 by default).
- The MCP service is reached on the node's loopback interface through SSH; it does not need to be exposed directly to the network.
- Each deployment needs a unique, available local tunnel port on the central host. The checked-in inventory uses `13001` and `13002`; change them if they are already in use.
- Allow the edge nodes to reach the external registries, repositories, and model/package sources needed for deployment. No inbound public access to the MCP service is required.
