# MCP client example

Follow [Use the multimodal MCP server](../../docs/user-guide/how-to-guides/use-mcp-server.md) for deployment and the tool reference.

This example calls one tool at a time on the deployed MCP server. Deploy the stack with `make up_agentic MCP=true` first. The client reads `MCP_USERNAME`, `MCP_PASSWORD`, `HOST_IP`, and `GRAFANA_PORT` from the project root `.env` and connects to `https://HOST_IP:GRAFANA_PORT/mcp` by default.

From the project root, set up a Python environment for the example:

```sh
cd mcp-server/example
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

Try a read-only call:

```sh
.venv/bin/python example_client.py --insecure describe
```

Call other tools independently:

```sh
.venv/bin/python example_client.py --insecure list_insights_data --page 1 --page-size 10
.venv/bin/python example_client.py --insecure explain --selected-time 2026-10-17T12:00:00Z
.venv/bin/python example_client.py --insecure run_agent --time-range 30s
.venv/bin/python example_client.py --insecure get_run_results --run-id YOUR_RUN_UUID
.venv/bin/python example_client.py --insecure start_pipeline --vision-inf-device CPU --time-series-inf-device CPU
.venv/bin/python example_client.py --insecure stop_pipeline
```

`start_pipeline`, `stop_pipeline`, and `run_agent` affect live processing. Only use them on a deployment you intend to control. Run `.venv/bin/python example_client.py --help` for all options; `--url https://HOST:PORT/mcp` overrides the address from `.env`.

The bundled nginx certificate is self-signed, so `--insecure` disables certificate verification for these local examples. For verified HTTPS, provide a trusted certificate matching the gateway hostname or IP and omit `--insecure`.