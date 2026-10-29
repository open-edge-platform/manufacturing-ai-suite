# Example prompt: agentic deploy with the MCP server

> Deploy the weld defect detection app in agentic mode with the MCP server,
> check that the MCP endpoint works, and start processing on CPU.

Expected agent flow:
1. Resolve app root, check `.env` (credentials, IPv4 `HOST_IP`, and
   non-empty `MCP_USERNAME`/`MCP_PASSWORD`), run Docker preflight. Ask the
   user for MCP credentials if they are unset; do not invent them.
2. Meet the prerequisites in
   [Deploy the agent workflow](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-agent-workflow.html):
   `make check_hardware`, then `make check_models`. If `check_models` fails,
   run **Download Models** from
   [Deploy the vLLM service](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/how-to-guides/how-to-deploy-vllm-service.html)
   only after the user explicitly accepts the model license (asked
   separately from the deploy request), and re-run `make check_models`.
   Inspect `configs/vllm/huggingface` and `configs/vllm/models` first; if
   either has content, do not run the doc's `rm -rf huggingface models`
   without explicit permission — download only the missing artifact.
3. `make build MCP=true` (only if images must be built locally).
4. `make up_agentic MCP=true` (hardware/model gates, then the agentic LLM
   download via `make download_model`).
5. `<skill-dir>/scripts/smoke-check.sh` — includes an authenticated,
   read-only MCP `tools/list` probe.
6. Explain that pipelines do not auto-start in MCP mode, so Grafana is
   empty until `start_pipeline` is called.
7. After the user confirms, run the example client from
   `mcp-server/example/`: `describe`, then
   `start_pipeline --vision-inf-device CPU --time-series-inf-device CPU`,
   then `list_insights_data`.
8. Report real command output and a clear PASS/FAIL summary. Do not print
   the MCP credentials.
9. Offer `stop_pipeline` and `make down MCP=true` for cleanup.
