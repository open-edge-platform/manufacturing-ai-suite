# Use Hermes as an Operator

Begin after the administrator has deployed the applications, verified MCP registration, and provided approved access to Hermes. Operators do not need to rerun the installer for normal queries.

## Open the WebUI

On the central host, open <http://127.0.0.1:8787/> and log in with the WebUI password supplied securely by the administrator.

Keep that SSH session open, then visit <http://127.0.0.1:8787/> on your workstation. If local port `8787` is occupied, use a different local port, for example `-L 8788:127.0.0.1:8787`, and open <http://127.0.0.1:8788/> instead. This browser-access tunnel is separate from the administrator-managed MCP tunnels to the edge nodes.

## Choose the right profile

- Select **`default`** for fleet queries through the registered MCP tools. In the checked-in inventory, the MCP servers are named `node1` and `node2`.
- Node profiles such as **`node1`** and **`node2`** run terminal commands on their corresponding edge nodes over SSH. Use these only for administrator-approved node-specific work; they are not required for normal MCP queries.

Start a new chat after MCP registrations change. In a CLI chat, `/reload-mcp` can reload the registrations. The central host's MCP tunnels and the remote applications must remain running while you use their tools.

## Use natural-language requests

After registration, operators use the default Hermes profile and address servers by their inventory deployment name. For example:

> Describe node1 and node2, then compare their current status.

Before requesting a processing change, ask Hermes to describe the selected application's pipeline controls and required options:

> Describe the pipeline controls available on node1 and the options needed to start processing. Do not start it yet.

Or query recent data:

> Show the latest 10 insights from node1 and summarize the results, including the time range.

Starting or stopping a live pipeline changes processing. Review the requested action and confirm it is intended before authorizing it. The available tools and accepted options depend on the recipe configured for that deployment.

## Use the CLI instead of the WebUI

If authorized to use the central Hermes account, start a chat from the central host:

```bash
hermes
```

Use the same natural-language requests as in the browser. If tools are missing, a tunnel is unavailable, or authentication fails, report the affected server and error to the administrator. Do not paste passwords, tokens, or private keys into chat.
