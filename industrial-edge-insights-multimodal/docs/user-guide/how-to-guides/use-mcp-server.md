# Use the multimodal MCP server

The optional Model Context Protocol (MCP) server exposes the weld defect detection sample app to MCP clients.
It uses Python/FastMCP and Streamable HTTP through the existing HTTPS gateway at `/mcp`.
Grafana, the data ingestion paths, and the agentic UI remain unchanged.

## Prerequisites

- Complete the [Get Started prerequisites](../get-started.md).
- Meet the requirements of the [agentic workflow](./how-to-deploy-agent-workflow.md), including the vLLM model download.
  The MCP server is deployed only with the agentic stack.
- Use Python 3.12 or later for the example client.
- Set `HOST_IP` in `.env` to the gateway's IPv4 address.

## Deploy

**Caution:** `make up_agentic` stops the existing stack and removes its volumes.
Use it only on a deployment that you intend to replace.

1. Set MCP credentials in `.env`:

   ```bash
   MCP_USERNAME=mcpuser
   MCP_PASSWORD=<your-password>
   ```

   The username must contain only alphabets and be at least 5 characters long.
   The password must be at least 10 alphanumeric characters with at least one letter and one digit.
   `make check_env_variables MCP=true` validates both values.
   Never commit credentials.

2. Build the images:

   ```bash
   make build
   ```

   `make build` also builds the MCP server image; a published MCP image is not required.
   `DOCKER_REGISTRY` and `MULTIMODAL_MCP_SERVER_IMAGE` control its registry and repository.
   Runtime package versions are pinned in `mcp-server/requirements.txt`.

3. Deploy the agentic stack with the MCP server:

   ```bash
   make up_agentic MCP=true
   ```

   Pipelines do not start automatically in this mode.
   The time-series UDF package is not uploaded during deployment either.
   Both are done by the `start_pipeline` tool.
   Without `MCP=true`, `make up_agentic` retains the automatic startup and does not deploy the MCP server.

## Use the example client

The example client reads `MCP_USERNAME`, `MCP_PASSWORD`, `HOST_IP`, and `GRAFANA_PORT` from `.env`
and connects to `https://HOST_IP:GRAFANA_PORT/mcp`.

From the component root:

```bash
python3 -m venv mcp-server/example/.venv
mcp-server/example/.venv/bin/pip install -r mcp-server/example/requirements.txt
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure describe
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure start_pipeline \
  --vision-inf-device CPU --time-series-inf-device CPU
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure list_insights_data \
  --page 1 --page-size 10
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure explain \
  --selected-time 2026-10-17T12:00:00Z
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure run_agent --time-range 30s
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure get_run_results \
  --run-id YOUR_RUN_UUID
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py --insecure stop_pipeline
```

The local gateway uses a self-signed certificate, so the example client needs `--insecure`.
Use `--url https://HOST:PORT/mcp` to override the address from `.env`.
For production, provision an organization-trusted certificate and key, and do not use `--insecure`.

`start_pipeline` selects the vision device (`CPU`, `GPU`, or `NPU`) and the time-series device (`CPU` or `GPU`) independently.
The MCP container itself does not require a GPU or NPU.

**Caution:** `start_pipeline`, `stop_pipeline`, and `run_agent` affect live processing.
Use them only on a deployment that you intend to control.

## Tools

| Tool | Result |
|---|---|
| `describe` | Registered tools, input schemas, and operational guidance |
| `start_pipeline` | Uploads the time-series UDF package, applies its config, waits until the task is enabled, then starts the weld classification pipeline |
| `stop_pipeline` | Stops all queued or running DL Streamer pipelines and disables the weld time-series task |
| `list_insights_data` | Paginated fusion results (`page`, `page_size`) |
| `explain` | Explanation of one fused detection, selected by its ISO-8601 timestamp |
| `run_agent` | Starts an agentic analysis over `30s`, `1m`, `5m`, `10m`, or `30m` and returns the run ID |
| `get_run_results` | Status of an agent run (`reasoning`, `completed`, or `error`) and its result once completed |

All MCP requests require the Basic-auth credentials from `.env`, including initialization and discovery.
Requests without valid credentials receive HTTP 401.
Partial failures in `start_pipeline` and `stop_pipeline` list the stages that completed and the ones that failed.

`explain` and `run_agent` depend on the vLLM and agentic services.
Agent and model-generated analysis is advisory; review results before making operational or safety decisions.

The server does not expose arbitrary commands, queries, or uploads from clients.
Upstream errors are returned as sanitized tool failures.

## Validate and stop

```bash
make status
make down MCP=true
```

Use `MCP=true` for `down` so the MCP server is removed with the rest of the stack.
The server port is internal; only nginx exposes `/mcp`.
