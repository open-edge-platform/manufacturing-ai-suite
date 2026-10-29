# Time-series MCP client

Follow [Use the time-series MCP server](../../docs/user-guide/how-to-guides/use-mcp-server.md)
to deploy, trust the gateway certificate, and run this client.

The client reads `MCP_USERNAME`, `MCP_PASSWORD`, `MCP_URL`, and `MCP_CA_FILE`
from the process environment. It does not read or print the deployment's environment file.
Run `python example_client.py --help` to see the options.
