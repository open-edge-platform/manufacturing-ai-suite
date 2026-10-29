# Use the time-series MCP server

The optional Model Context Protocol (MCP) server exposes wind-turbine analytics to MCP clients.
It uses Python/FastMCP and Streamable HTTP through the existing HTTPS gateway.
Grafana and the sensor ingestion paths remain unchanged.

## Prerequisites

- Complete the [Get Started prerequisites](../get-started.md).
- Use Python 3.12 or later for the example client.
- Set the existing database and Grafana credentials.
- Set `HOST_IP` to the gateway's IPv4 address.
- Use an analytics image with `/config`, `/udfs/package`, and the native Kapacitor task API.

The server uses Kapacitor directly for task status and stop operations.
It does not require the newer microservice `/pipeline_status` or `/stop_pipeline` endpoints.

## Deploy

**Caution:** Deployment targets stop the existing stack and remove its volumes.
Use them only on a deployment that you intend to replace.

1. Set MCP credentials in the same shell:

   Set `MCP_USERNAME` and `MCP_PASSWORD` in `.env`:

   ```bash
   MCP_USERNAME=mcpuser
   MCP_PASSWORD=<your-password>
   ```

   The username must contain only alphabets and be at least 5 characters long.
   The password must be at least 10 alphanumeric characters with at least one letter and one digit.
   `make check_env_variables MCP=true` validates both values.
   Never commit credentials.

2. Build the server:

   ```bash
   make build
   ```

   The MCP image is built locally; a published MCP image is not required.
   Runtime package versions are pinned in `mcp-server/requirements.txt`, but
   transitive dependencies are not hash-locked.
   `DOCKER_REGISTRY` and `TIME_SERIES_MCP_IMAGE` control its registry and repository.
   Its default tag is `2026.1.0`.

3. Select one ingestion path:

   ```bash
   make up_mqtt_ingestion MCP=true
   # Or:
   make up_opcua_ingestion MCP=true
   ```

   Analytics waits for `start_pipeline`; these commands do not upload or activate the UDF.
   Without `MCP=true`, both commands retain automatic analytics startup.

4. For batch processing, append `batch` during deployment:

   ```bash
   make up_mqtt_ingestion batch MCP=true
   ```

   The server selects the batch UDF and creates its model alias inside the upload archive.
   It does not modify application assets.
   Batch results use a 20-minute window.

`num_of_streams` and `INCLUDE=validation` retain their existing behavior.
System metrics remain available in Grafana when collected; this MCP version does not expose host metrics.

## Trust the gateway certificate

All MCP requests require Basic authentication over verified HTTPS, including initialization and discovery.
There is no insecure client option.

The local gateway creates a self-signed certificate with `localhost` and `HOST_IP` subject alternative names.
Obtain this certificate through a trusted local connection:

```bash
docker compose -f docker-compose.yml -f docker-compose-mcp.yml \
  exec -T nginx cat /opt/nginx/certs/cert.pem > ./mcp-gateway-ca.pem
export MCP_CA_FILE="$PWD/mcp-gateway-ca.pem"
export MCP_URL="https://127.0.0.1:3000/mcp"
```

Replace the address and port with the configured `HOST_IP` and `GRAFANA_PORT`.
Store the certificate outside version control.
The gateway regenerates its certificate on restart; obtain the new certificate after a restart.
For production, provision an organization-trusted certificate and key instead of the local certificate-generation step.

## Use the example client

From the component root:

```bash
python3 -m venv mcp-server/example/.venv
mcp-server/example/.venv/bin/pip install -r mcp-server/requirements.txt
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py describe
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py get_pipeline_status
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py start_pipeline \
  --arguments '{"time_series_inf_device":"CPU"}'
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py list_insights_data \
  --arguments '{"severity":"anomaly","page":1,"page_size":20}'
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py get_anomaly_summary
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py get_processing_metrics
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py list_sources
mcp-server/example/.venv/bin/python mcp-server/example/example_client.py stop_pipeline
```

`GPU` is also supported by `start_pipeline` when the analytics container has suitable hardware.
The MCP container itself does not require a GPU.
Device changes retain the active alert configuration.
The server rejects control requests when a different UDF task is configured.

**Caution:** `stop_pipeline` disables analytics only.
Sensor ingestion and containers continue running.
Streaming input received while analytics is disabled is not replayed automatically.
One-shot simulators can exhaust their input before analytics starts; use continuous ingestion for interactive demonstrations.

## Tool data contract

| Tool | Result |
|---|---|
| `describe` | Tools, schemas, processing mode, classification codes, and operational guidance |
| `get_pipeline_status` | Daemon health and selected task state, including `not_configured` |
| `start_pipeline` | Verified enabled state, selected device, and change indicator |
| `stop_pipeline` | Verified disabled state or an explicit unconfigured state |
| `list_sources` | Paginated source identifiers observed in the requested time window |
| `list_insights_data` | Paginated points, classification, analysis flag, and timing values in seconds |
| `get_anomaly_summary` | Processed, analysed, unanalysed, anomalous, and per-severity counts |
| `get_processing_metrics` | Counts, window-average rates, mean latencies, and last-observed timestamps |

Data tools accept `start_time` and `end_time` as timezone-aware timestamps.
The default window covers the preceding 30 minutes; the maximum window is 24 hours.
The start is inclusive and the end is exclusive.
Use an explicit, fixed window while paging through results.
List tools accept `page` and `page_size`, with at most 100 entries per page.
They return `has_more` and `next_page`, not an expensive unrestricted total count.
Point, summary, and metrics tools support an exact `source` filter.
Source identifiers support up to 128 letters, digits, underscores, dots, colons, and hyphens.
`list_insights_data` supports `all`, `anomaly`, `normal`, `low`, `medium`, and `high` severity filters.

Classification codes are `0`, `0.3`, `0.6`, and `1.0`; they are not confidence scores.
The analysis flag distinguishes unanalysed points from analysed points.
Anomaly percentage uses analysed points as its denominator.
Missing timing values and percentages without analysed points are `null`, not zero.
Rates divide retained point counts by the requested window duration in minutes.
They differ from Grafana's fixed three-minute rolling queries.
Counts cannot include expired data; the stack defaults to one-hour retention.

The server does not expose arbitrary InfluxQL, uploads from clients, shell commands, vision, fusion, or LLM explanations.
Database and analytics errors are explicit, sanitized tool failures.
Partial startup failures identify the completed deployment stages.
The existing database user has broad privileges; provision a separate read-only database identity for MCP when deployment policy requires it.

## Validate and stop

```bash
make status MCP=true
make down MCP=true
```

Use `MCP=true` consistently for deployment, status, and shutdown.
The server port is internal; only nginx exposes `/mcp`.
Its internal `/health` endpoint provides liveness and does not require credentials.
Browser origins must match the configured HTTPS gateway origin.

For tests, see the [MCP testing instructions](../../../tests/README.md#mcp-server-tests).
