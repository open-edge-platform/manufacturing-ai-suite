# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

"""Call one tool on an authenticated time-series MCP deployment."""

import argparse
import asyncio
import base64
import json
import os
import ssl
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport
from fastmcp.exceptions import ToolError
import httpx


async def main():
    """Read credentials from the environment and verify the server certificate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", help="Tool name, for example describe or get_anomaly_summary")
    parser.add_argument("--arguments", default="{}", help="JSON object containing tool arguments")
    parser.add_argument("--url", default=os.getenv("MCP_URL", "https://127.0.0.1:3000/mcp"))
    parser.add_argument(
        "--ca-file", default=os.getenv("MCP_CA_FILE"), help="Trusted gateway CA or certificate"
    )
    args = parser.parse_args()
    username = os.getenv("MCP_USERNAME")
    password = os.getenv("MCP_PASSWORD")
    if not username or not password:
        parser.error("Set MCP_USERNAME and MCP_PASSWORD in the environment")
    if not args.url.startswith("https://"):
        parser.error("Use an HTTPS MCP URL")
    try:
        arguments = json.loads(args.arguments)
    except json.JSONDecodeError:
        parser.error("--arguments must be valid JSON")
    if not isinstance(arguments, dict):
        parser.error("--arguments must be a JSON object")
    authorization = base64.b64encode(f"{username}:{password}".encode()).decode()
    context = ssl.create_default_context(cafile=args.ca_file)
    transport = StreamableHttpTransport(
        args.url,
        headers={"Authorization": "Basic " + authorization},
        verify=context,
    )
    try:
        async with Client(transport, timeout=300) as client:
            result = await client.call_tool(args.tool, arguments)
            print(json.dumps(result.data, indent=2))
    except ToolError as error:
        print(f"MCP tool failed: {error}", file=sys.stderr)
        return 1
    except (httpx.HTTPError, RuntimeError) as error:
        print(
            f"MCP call failed ({type(error).__name__}); "
            "check the endpoint, certificate, credentials and tool arguments.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
