# Install Hermes, Set the Persona, and Bring Up the WebUI

Do the tasks on this page on the **central host**. Use the same user account that will run the fleet setup. Do not do them on the edge nodes.

The sections are in order:

1. [Install Hermes with a local model](#install-hermes-with-a-local-model)
2. [Verify the local model](#verify-the-local-model)
3. [Set the persona](#set-the-factory-defects-inspector-agent-persona)
4. [Bring up the Hermes WebUI (optional)](#bring-up-the-hermes-webui-optional)

## Install Hermes with a local model

The [Agent Harness Installer](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/frameworks/agent-harness-install) installs Hermes. It also installs a local OpenVINO Model Server (OVMS) and an Inference Router.

**Before you start:**

- Read the [get-started prerequisites](https://github.com/open-edge-platform/edge-ai-libraries/blob/main/frameworks/agent-harness-install/docs/user-guide/get-started.md) of the installer.
- For a GPU install, make sure that the Intel GPU driver and compute runtime are installed.
- Make sure that the host has enough memory and disk space for the model and the container images.
- Review the license of the [OpenVINO/Qwen3.5-9B-int8-ov](https://huggingface.co/OpenVINO/Qwen3.5-9B-int8-ov) model prior to deployment.
- For a reproducible deployment, use the reviewed repository revision of your site.
- If your network needs a proxy, set it in the installer environment before you run the installer.

**Caution:** The installer can change the Docker daemon proxy and restart Docker. Run it on a host where a Docker restart does not interrupt other workloads.

1. Clone the installer repository:

   ```bash
   git clone https://github.com/open-edge-platform/edge-ai-libraries.git
   cd edge-ai-libraries/frameworks/agent-harness-install
   ```

2. Install Hermes with the OVMS image and the model:

   >**Note**: Go with the default values during the `./install.sh` execution

   ```bash
   HARNESS_OVMS_IMAGE=openvino/model_server:2026.4.1-gpu \
   ./install.sh --harness hermes --model OpenVINO/Qwen3.5-9B-int8-ov
   ```

3. Read the install output. Make sure that the model registration is successful. A completed download is not sufficient.

OVMS serves the model through the Inference Router. Hermes uses this local model for all inference.

The installer prepares the host, starts OVMS and the Inference Router, downloads the model, and installs Hermes. The `OpenVINO/*` models are pre-converted. OVMS serves the model only if the downloaded repository has the `graph.pbtxt` file.

If the model needs access credentials, supply them through environment variables. Do not put them in the command or the inventory.

## Verify the local model

The installer does not configure or test Hermes. Do these steps to configure and test it.

1. Find the `hermes config set` commands in the installer output. They point Hermes to the Inference Router. Do not use the OVMS endpoint directly.

2. Run the commands. Example:

   ```bash
   hermes config set model.provider custom
   hermes config set model.base_url http://127.0.0.1:8010/v1
   hermes config set model.default Qwen3.5-9B-int8-ov
   ```

   Use the values from your installer output. The base URL is the Inference Router and ends in `/v1`. `model.default` is the served model name.

3. If the installer reports that the router needs an API key, set the key as the installer output says. Do not put the key in a file that you commit.

4. Start a test chat:

   ```bash
   hermes
   ```

5. Ask a simple question. Make sure that Hermes gives a response.

If the model does not respond, do not continue. Fix the problem first:

- Run `./install.sh status` in the installer checkout. It shows the health of OVMS, the router, and the agent.
- Run `./install.sh models list`. It shows if the model is served.

When the model responds, return to the `factory-defects-inspector-agent` directory of this repository.

**Note:** The fleet installer clones each node profile from the default profile. The node profiles inherit the model configuration. If you change the default model, run `fleet-setup.sh` again to recreate the node profiles. After deployment, test the MCP tool calls with this model. Tool-calling behavior depends on the model.

To use a hosted provider, run `hermes setup model`. Get approval for the provider and model from your administrator first. A hosted provider can receive prompts and tool results. Use it only with data that the provider is approved for.

## Set the Factory Defects Inspector Agent persona

`SOUL.md` is the persona template for this agent. It defines these items:

- The purpose of the assistant.
- Evidence-based reporting.
- The administrator and operator workflows.
- The confirmation boundaries for operational changes.

`SOUL.md` has no node addresses, credentials, or model selections.

**Install the persona before you run the fleet installer.** The installer clones each node profile from the default profile. The clone copies `SOUL.md` at that time. A persona that you install later reaches the node profiles only when you run the installer again.

1. Read `SOUL.md`.

2. From the `factory-defects-inspector-agent` directory, run:

   ```bash
   ./hermes-webui.sh persona
   ```

   The command installs `SOUL.md` in the Hermes home. The default is `~/.hermes`. If `HERMES_HOME` is set, it uses that directory. The file has owner-only permissions.

   If the installed persona is identical, the command does nothing. If it is different, the command saves the old persona to `SOUL.md.backup.<timestamp>` and replaces it.

3. If the old persona has customizations that you need, merge them into the new file. Keep the backup until you verify the new behavior.

4. Start a new chat on the default profile, in the CLI or the WebUI.

5. Ask the agent to explain its role. Ask how it handles a request to stop a pipeline.

6. Make sure that the agent identifies the target and asks for approval. It must not make a change.

**Note:** The persona is behavioral guidance. It is not access control. The fleet installer never installs or overwrites the persona of the default profile. A change to the template does not change an existing Hermes installation.

`./hermes-webui.sh setup` does the persona installation and the WebUI start in one command.

## Bring up the Hermes WebUI (optional)

The Hermes WebUI is community software. It gives browser-based chat for the local Hermes installation. It is not a part of the fleet deployment. You can start it now or after the fleet deployment.

**Warning:** The WebUI gives terminal and file access with the permissions of the central Hermes user. The administrator and operator roles in this guide are not access-control roles. Give access only to trusted operators. A profile selection is not a security boundary.

**Before you start, make sure that:**

- `git`, Python 3, and `curl` are installed.
- The host can reach the WebUI Git repository.
- `~/.hermes/config.yaml` exists. If `HERMES_HOME` is set, check that directory.
- Local port `8787` is free.

**Start the WebUI:**

1. Run the command as the user who configured Hermes. Use the `factory-defects-inspector-agent` directory:

   ```bash
   ./hermes-webui.sh start
   ```

2. On the first run, the script clones the WebUI to `~/hermes-webui`. It checks out the pinned release `v0.52.492`.

3. When the script asks, enter a password and repeat it. The password must have at least 12 characters. It must not contain quotes. Without a terminal, the script generates a password.

4. Wait for the message that the WebUI is up. The script stores the settings in `~/hermes-webui/.env` with mode `600`. It starts the daemon and checks the `/health` endpoint.

5. Open <http://127.0.0.1:8787/>.

To choose the bind address, add `--host <ADDR>` to `start` or `setup`.

### Remote access

Use loopback with SSH forwarding. Keep password login on.

To set loopback again on an existing installation:

```bash
HERMES_WEBUI_HOST=127.0.0.1 ./hermes-webui.sh restart
```

**Caution:** Direct HTTP sends passwords and chat content without encryption. Use a firewall to limit access to authorized clients. Prefer SSH forwarding or a TLS reverse proxy. Do not expose the plain-HTTP service to an untrusted network.

To give direct access on a trusted network:

1. Set `HERMES_WEBUI_HOST` to an IPv4 address of the central host. Use `0.0.0.0` for all IPv4 interfaces:

   ```bash
   HERMES_WEBUI_HOST=0.0.0.0 ./hermes-webui.sh restart
   ```

   The option `--host 0.0.0.0` does the same.

2. Open `http://<central-host-ip>:8787/` from the remote system. `0.0.0.0` is not a browser address.

The script saves the bind address for the next starts.

### Manage the WebUI

| Command | Action |
| --- | --- |
| `./hermes-webui.sh status` | Show the status. |
| `./hermes-webui.sh logs` | Show the logs. |
| `./hermes-webui.sh restart` | Restart the daemon. |
| `./hermes-webui.sh stop` | Stop the daemon. |
| `./hermes-webui.sh start` | Install if necessary, then start. |
| `./hermes-webui.sh install` | Install or update to the pinned release. Does not start. |
| `./hermes-webui.sh persona` | Install the persona only. |
| `./hermes-webui.sh setup` | Install, install the persona, and start. |

To override the defaults, set `HERMES_WEBUI_DIR`, `HERMES_WEBUI_VERSION`, or `HERMES_WEBUI_PORT`. Use a reviewed stable release tag. If you change the port, change the browser URL and the SSH forwarding ports.
