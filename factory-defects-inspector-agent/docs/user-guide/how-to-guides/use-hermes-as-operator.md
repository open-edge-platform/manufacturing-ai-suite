# Use Hermes as an Operator

Start after the administrator has deployed the applications and verified the MCP registration. The administrator also gives you approved access to Hermes. You do not run the installer for normal queries.

## Open the WebUI

1. Get the WebUI password from the administrator.
2. On the central host, open <http://127.0.0.1:8787/>.
3. Log in with the password.

To open the WebUI from your workstation:

1. Open an SSH tunnel to the central host:

   ```bash
   ssh -L 8787:127.0.0.1:8787 <user>@<central-host>
   ```

2. Keep the SSH session open.
3. On your workstation, open <http://127.0.0.1:8787/>.

If local port `8787` is in use, use a different local port. For example, use `-L 8788:127.0.0.1:8787` and open <http://127.0.0.1:8788/>.

This tunnel is not the same as the MCP tunnels to the edge nodes. The administrator manages the MCP tunnels.

## Choose the profile

| Profile | Use |
| --- | --- |
| `default` | Fleet queries through the registered MCP tools. In the checked-in inventory, the MCP servers are `node1` and `node2`. |
| `node1`, `node2` | Terminal commands on the edge node over SSH. Use only for node-specific work that the administrator approves. Not necessary for normal MCP queries. |

After an MCP registration changes, start a new chat. In a CLI chat, you can run `/reload-mcp`. The MCP tunnels and the remote applications must stay running.

## Ask Hermes

Use the `default` profile. Use the deployment name from the inventory to select a server.

Example: describe the nodes.

> Describe node1 and node2, then compare their current status.

Example: read the recent data.

> Show the latest 10 insights from node1 and summarize the results, including the time range.

**Caution:** Starting or stopping a live pipeline changes processing. The available tools and options depend on the recipe of the deployment. Confirm an action only if you intend it.

To change processing, do these steps in order:

1. Ask Hermes to describe the pipeline controls. Example:

   > Describe the pipeline controls available on node1 and the options needed to start processing. Do not start it yet.

2. Review the action that you request.
3. Confirm the action.

## Use the CLI

If you have access to the central Hermes account, start a chat on the central host:

```bash
hermes
```

Use the same requests as in the browser.

If tools are missing, a tunnel is not available, or authentication fails, tell the administrator. Include the server name and the error. Do not paste passwords, tokens, or private keys in a chat.
