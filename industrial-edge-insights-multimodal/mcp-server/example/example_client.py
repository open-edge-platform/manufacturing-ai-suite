#
# Apache v2 license
# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#

"""Call one tool on a deployed weld-analysis MCP server.

Install requirements from mcp-server/requirements.txt, then run
python3 mcp-server/example/example_client.py --insecure describe from the project root.
To control a test deployment, run either command independently:
python3 mcp-server/example/example_client.py --insecure start_pipeline
python3 mcp-server/example/example_client.py --insecure stop_pipeline
These commands affect live processing.
"""

import argparse
import asyncio
import base64
import json
from pathlib import Path


ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


async def exercise(args: argparse.Namespace) -> None:
    from dotenv import dotenv_values
    from fastmcp import Client
    from fastmcp.client.transports import StreamableHttpTransport

    credentials = dotenv_values(ENV_FILE)
    username = credentials.get("MCP_USERNAME")
    password = credentials.get("MCP_PASSWORD")
    if not username or not password:
        raise ValueError(f"Set MCP_USERNAME and MCP_PASSWORD in {ENV_FILE}")

    encoded = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    host_ip = credentials.get("HOST_IP") or "localhost"
    port = credentials.get("GRAFANA_PORT") or "3000"
    transport = StreamableHttpTransport(
        url=args.url or f"https://{host_ip}:{port}/mcp",
        headers={"Authorization": f"Basic {encoded}"},
        verify=not args.insecure,
    )
    tool_arguments = vars(args).copy()
    for option in ("url", "insecure", "tool"):
        tool_arguments.pop(option)

    async with Client(transport, mode="legacy") as client:
        result = await client.call_tool(args.tool, tool_arguments)
        if result.is_error:
            raise RuntimeError(f"{args.tool} failed: {result.content}")
        print(json.dumps(result.data, indent=2))


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", help="Override the gateway URL from the project .env")
    parser.add_argument("--insecure", action="store_true", help="Trust the local self-signed HTTPS certificate")
    tools = parser.add_subparsers(dest="tool", required=True)
    tools.add_parser("describe", help="Describe the MCP server and its tools")

    insights = tools.add_parser("list_insights_data", help="List fusion results")
    insights.add_argument("--page", type=int, default=1)
    insights.add_argument("--page-size", type=int, default=10)

    explain = tools.add_parser("explain", help="Explain a fused detection")
    explain.add_argument("--selected-time", required=True, help="ISO-8601 fusion timestamp")

    agent = tools.add_parser("run_agent", help="Start an agentic analysis run")
    agent.add_argument("--time-range", choices=("30s", "1m", "5m", "10m", "30m"), default="30s")

    results = tools.add_parser("get_run_results", help="Inspect one agent run")
    results.add_argument("--run-id", required=True)

    start = tools.add_parser("start_pipeline", help="Start live detection")
    start.add_argument("--vision-inf-device", choices=("CPU", "GPU", "NPU"), default="CPU")
    start.add_argument("--time-series-inf-device", choices=("CPU", "GPU"), default="CPU")
    tools.add_parser("stop_pipeline", help="Stop live detection")
    return parser


def main() -> None:
    asyncio.run(exercise(create_parser().parse_args()))


if __name__ == "__main__":
    main()