# Bring Up Hermes WebUI

The optional community Hermes WebUI provides browser-based chat using the local Hermes installation. It is third-party software, not a separate fleet deployment service. Run `hermes-webui.sh` on the central host as the same user who configured Hermes and registered the MCP servers.

Before starting, ensure that:

- `git`, Python 3, and `curl` are available, with network access to the WebUI Git repository.
- Hermes is configured and its configuration file exists at `~/.hermes/config.yaml` (or under the configured `HERMES_HOME`).
- Local port `8787` is available.

From the `factory-defects-inspector-agent` directory, run:

```bash
bash ./hermes-webui.sh start
```

To combine installation, persona setup, and startup in one step, run `bash ./hermes-webui.sh setup` instead: it installs the WebUI if needed, installs the `SOUL.md` persona into the Hermes home (backing up any existing persona to `SOUL.md.backup.<timestamp>` first — see [Install Hermes and Set the Persona](../get-started/install-hermes.md)), and starts the daemon. Add `--host <ADDR>` to either command to choose the bind address at the same time.

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

The `--host` option is equivalent to the environment variable: `bash ./hermes-webui.sh --host 0.0.0.0 restart`.

Open `http://<central-host-ip>:8787/` from the remote system; `0.0.0.0` is a bind wildcard, not a browser destination. The script saves the bind address for subsequent starts. Restrict access to authorized clients with a firewall and prefer SSH forwarding or a TLS reverse proxy: direct HTTP sends passwords and chat content unencrypted.

Use these commands to manage it:

```bash
bash ./hermes-webui.sh status
bash ./hermes-webui.sh logs
bash ./hermes-webui.sh restart
bash ./hermes-webui.sh stop
```

`start` installs only if needed; `install` installs or updates to the configured pinned release but does not start the service; `setup` runs install, persona installation, and start together; `persona` installs only the persona. The script also accepts `HERMES_WEBUI_DIR`, `HERMES_WEBUI_VERSION`, and `HERMES_WEBUI_PORT` overrides. Use a reviewed stable release tag, and adjust the browser URL and SSH forwarding ports if you change the port.

**Access warning:** the WebUI includes terminal and file access with the central Hermes user's permissions. The administrator/operator personas in this guide describe responsibilities, not enforced access-control roles. Grant access only to trusted operators; do not treat a profile selection as a security boundary. Do not expose the plain-HTTP service directly to an untrusted network.
