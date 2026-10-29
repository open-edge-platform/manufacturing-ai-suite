# Install Hermes, Set the Persona, and Bring Up the WebUI

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

Ask a simple question and verify that it receives a response. Only then return to this repository's `factory-defects-inspector-agent` directory and continue with node preparation and fleet deployment.

When the integration issues are resolved, configure Hermes with the Inference Router's OpenAI-compatible endpoint and served model reported by the installer, not the OVMS endpoint directly. Keep the local backend bound to loopback and validate both inference and the fleet's MCP tool calls before replacing the temporary model configuration.


## Set the Factory Defects Inspector Agent persona

`SOUL.md` is a reusable Hermes persona template for this agent. It defines the assistant's purpose, evidence-based reporting, administrator/operator workflows, and confirmation boundaries for operational changes. It deliberately contains no node addresses, credentials, or fixed model selections; those remain in inventory, provider configuration, and live tool results.

Review the template before applying it. From the `factory-defects-inspector-agent` directory, as the central Hermes user:

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

To automate this step, run `./hermes-webui.sh persona` instead: it is a no-op when the installed persona already matches the template, and otherwise backs up the existing persona to `SOUL.md.backup.<timestamp>` before replacing it. `./hermes-webui.sh setup` combines persona installation with the optional WebUI bring-up described below.

Start a new default-profile Hermes chat (in the CLI, or in the WebUI if you have set it up — see the next section), and ask it to explain its role and how it handles a request to stop a pipeline. Confirm that it identifies the target and seeks approval rather than making a change.

**Install the persona before running the fleet installer.** The installer creates each node profile as a clone of the default profile, and the clone copies the default profile's `SOUL.md` at creation time — so node profiles automatically inherit whatever persona the default profile has when `fleet-setup.sh` runs. Because the installer recreates node profiles from the current default profile on every run, a persona installed or updated later is picked up by the next installer run; it does not propagate to existing node profiles by itself.

This is behavioral guidance, not an access-control mechanism. The fleet installer never installs or overwrites the default profile's persona, and changing this template alone does not change an existing Hermes installation.

## Bring up the Hermes WebUI (optional)

The optional community Hermes WebUI provides browser-based chat using the local Hermes installation. It is third-party software, not a separate fleet deployment service. Run `hermes-webui.sh` on the central host as the same user who configured Hermes and who runs the fleet setup. You can bring it up now or at any time after the fleet deployment.

Before starting, ensure that:

- `git`, Python 3, and `curl` are available, with network access to the WebUI Git repository.
- Hermes is configured and its configuration file exists at `~/.hermes/config.yaml` (or under the configured `HERMES_HOME`).
- Local port `8787` is available.

From the `factory-defects-inspector-agent` directory, run:

```bash
./hermes-webui.sh start
```

To combine installation, persona setup, and startup in one step, run `./hermes-webui.sh setup` instead: it installs the WebUI if needed, installs the `SOUL.md` persona into the Hermes home (backing up any existing persona to `SOUL.md.backup.<timestamp>` first, as described in the persona section above), and starts the daemon. Add `--host <ADDR>` to either command to choose the bind address at the same time.

On the first run, the script clones the WebUI into `~/hermes-webui`, checks out the pinned release `v0.52.492`, and asks you to choose and repeat a password. The password must be at least 12 characters and cannot contain quotes. Run this interactively to set the password yourself; without a terminal, the script generates one instead.

The script stores the WebUI settings in `~/hermes-webui/.env` with mode `600`, starts the daemon, and checks its `/health` endpoint. Wait for the message that the WebUI is up before handing access to the operator.

The default address is <http://127.0.0.1:8787/>. Keep password login enabled and prefer loopback with SSH forwarding for remote access. For an existing installation previously bound to another address, restore loopback explicitly:

```bash
HERMES_WEBUI_HOST=127.0.0.1 ./hermes-webui.sh restart
```

For direct access from a remote system on a trusted network, set `HERMES_WEBUI_HOST` to an IPv4 address assigned to the central host, or use `0.0.0.0` to listen on all IPv4 interfaces:

```bash
# Alternatively, replace 0.0.0.0 with the central host's own IPv4 address.
HERMES_WEBUI_HOST=0.0.0.0 ./hermes-webui.sh restart
```

The `--host` option is equivalent to the environment variable: `./hermes-webui.sh --host 0.0.0.0 restart`.

Open `http://<central-host-ip>:8787/` from the remote system; `0.0.0.0` is a bind wildcard, not a browser destination. The script saves the bind address for subsequent starts. Restrict access to authorized clients with a firewall and prefer SSH forwarding or a TLS reverse proxy: direct HTTP sends passwords and chat content unencrypted.

Use these commands to manage it:

```bash
./hermes-webui.sh status
./hermes-webui.sh logs
./hermes-webui.sh restart
./hermes-webui.sh stop
```

`start` installs only if needed; `install` installs or updates to the configured pinned release but does not start the service; `setup` runs install, persona installation, and start together; `persona` installs only the persona. The script also accepts `HERMES_WEBUI_DIR`, `HERMES_WEBUI_VERSION`, and `HERMES_WEBUI_PORT` overrides. Use a reviewed stable release tag, and adjust the browser URL and SSH forwarding ports if you change the port.

**Access warning:** the WebUI includes terminal and file access with the central Hermes user's permissions. The administrator/operator personas in this guide describe responsibilities, not enforced access-control roles. Grant access only to trusted operators; do not treat a profile selection as a security boundary. Do not expose the plain-HTTP service directly to an untrusted network.
