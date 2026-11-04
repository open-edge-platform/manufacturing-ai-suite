# Redeploy and Handle Credentials

Read these rules before you deploy again.

**Caution:** A recipe deployment replaces its managed checkout. A normal deployment can delete local `.env` values, downloaded models, and edits in the checkout. Back up what you must keep. Be ready to restore secrets that you supplied manually.

## Reconnect without a redeployment

Use `--no-deploy` when the application already runs. It reconnects Hermes only.

- It does not prepare the node, copy source code, or change the checkout or its `.env`.
- It reads the MCP credentials from the application `.env` over SSH.
- It restarts the tunnel and rewrites the MCP registration.

For the steps, see [Connect applications that are already running](../get-started/deploy-the-fleet.md#connect-applications-that-are-already-running).

## Handle secrets

- Do not put secrets in `hosts.yaml` or in a chat. The inventory has variable names and configuration, not credential values.
- The installer generates missing application credentials. It sends them over SSH.
- The installer stores the MCP credentials on the central host with restricted permissions.

## Protect Docker access

Membership in the `docker` group of a node gives root-equivalent access. Use a dedicated deployment account. Protect its SSH key.
