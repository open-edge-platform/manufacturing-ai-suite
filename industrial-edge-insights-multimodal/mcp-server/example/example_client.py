#
# Apache v2 license
# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#

"""Call one tool on an authenticated multimodal MCP deployment."""

import argparse
import asyncio
import base64
import json
import os
from pathlib import Path
import ssl
import sys

from dotenv import dotenv_values
from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport
from fastmcp.exceptions import ToolError
import httpx
from mcp.shared.exceptions import MCPError

ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


async def main():
    """Read settings from the environment or project .env and verify the server certificate."""
    try:
        env_file_values = dotenv_values(ENV_FILE)
    except (OSError, UnicodeDecodeError) as error:
        print(f"Ignoring unreadable {ENV_FILE} ({type(error).__name__})", file=sys.stderr)
        env_file_values = {}
    settings = {**env_file_values, **os.environ}
    default_url = (
        f"https://{settings.get('HOST_IP') or '127.0.0.1'}:{settings.get('GRAFANA_PORT') or '3000'}/mcp"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tool", help="Tool name, for example describe or get_pipeline_status")
    parser.add_argument("--arguments", default="{}", help="JSON object containing tool arguments")
    parser.add_argument("--url", default=settings.get("MCP_URL") or default_url)
    parser.add_argument(
        "--ca-file", default=settings.get("MCP_CA_FILE"), help="Trusted gateway CA or certificate"
    )
    args = parser.parse_args()
    username = settings.get("MCP_USERNAME")
    password = settings.get("MCP_PASSWORD")
    if not username or not password:
        parser.error(f"Set MCP_USERNAME and MCP_PASSWORD in the environment or {ENV_FILE}")
    if not args.url.startswith("https://"):
        parser.error("Use an HTTPS MCP URL")
    try:
        arguments = json.loads(args.arguments)
    except json.JSONDecodeError:
        parser.error("--arguments must be valid JSON")
    if not isinstance(arguments, dict):
        parser.error("--arguments must be a JSON object")
    authorization = base64.b64encode(f"{username}:{password}".encode()).decode()
    try:
        context = ssl.create_default_context(cafile=args.ca_file)
    except (OSError, ssl.SSLError) as error:
        parser.error(f"Cannot load the CA file {args.ca_file}: {error.__class__.__name__}")
    transport = StreamableHttpTransport(
        args.url,
        headers={"Authorization": "Basic " + authorization},
        verify=context,
    )
    try:
        async with Client(transport, mode="legacy", timeout=300) as client:
            result = await client.call_tool(args.tool, arguments)
            if result.is_error:
                raise ToolError(result.content)
            print(json.dumps(result.data, indent=2))
    except ToolError as error:
        print(f"MCP tool failed: {error}", file=sys.stderr)
        return 1
    except (httpx.HTTPError, MCPError, RuntimeError) as error:
        print(
            f"MCP call failed ({type(error).__name__}); "
            "check the endpoint, certificate, credentials and tool arguments.",
            file=sys.stderr,
        )
        return 1
    except Exception as error:  # noqa: BLE001 - last resort so the CLI never prints a traceback
        print(f"Unexpected error ({type(error).__name__}) while calling the MCP server.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        sys.exit(130)
