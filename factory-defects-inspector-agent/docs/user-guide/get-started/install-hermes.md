# Install Hermes and Set the Persona

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

Start a new default-profile Hermes chat, including in the WebUI, and ask it to explain its role and how it handles a request to stop a pipeline. Confirm that it identifies the target and seeks approval rather than making a change. Review any profile-specific persona separately; these instructions do not install the template into node profiles.

This is behavioral guidance, not an access-control mechanism. The fleet installer does not automatically install or overwrite the persona, and changing this template alone does not change an existing Hermes installation.
