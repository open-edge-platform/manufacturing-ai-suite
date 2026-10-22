# Example prompt: agentic deploy with the MCP server

> Deploy the weld defect detection app in agentic mode with the MCP server,
> check that the MCP endpoint works, and start processing on CPU.

Expected agent flow:
1. Resolve app root, check `.env` (credentials, IPv4 `HOST_IP`, and
   non-empty `MCP_USERNAME`/`MCP_PASSWORD`), run Docker preflight. Ask the
   user for MCP credentials if they are unset; do not invent them.
2. `make build MCP=true` (only if images must be built locally).
3. `make up_agentic MCP=true` (hardware gate + model download first).
4. `.github/skills/multimodal-deploy/scripts/smoke-check.sh` — includes the
   read-only MCP `tools/list` probe.
5. Explain that pipelines do not auto-start in MCP mode, so Grafana is
   empty until `start_pipeline` is called.
6. After the user confirms, run the example client from
   `mcp-server/example/`: `describe`, then
   `start_pipeline --vision-inf-device CPU --time-series-inf-device CPU`,
   then `list_insights_data`.
7. Report real command output and a clear PASS/FAIL summary. Do not print
   the MCP credentials.
8. Offer `stop_pipeline` and `make down MCP=true` for cleanup.
