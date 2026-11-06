# Redeploy and Handle Credentials

Read these rules before you deploy again.

**Caution:** A recipe deployment replaces its managed checkout. A normal deployment can delete local `.env` values, downloaded models, and edits in the checkout. Back up what you must keep. Be ready to restore secrets that you supplied manually.

## Reconnect without a redeployment

Use `--no-deploy` when the application already runs. It reconnects Hermes only.

- It does not prepare the node, copy source code, or change the checkout or its `.env`.
- It reads the MCP credentials from the application `.env` over SSH.
- It restarts the tunnel and rewrites the MCP registration.

For the steps, see [Connect applications that are already running](../get-started/deploy-the-fleet.md#connect-applications-that-are-already-running).

## Restore user lingering

The SSH tunnels to the node MCP servers are systemd user units (`fleet-tunnel@<name>`). systemd stops the services of a user when the last session of that user ends. To keep the tunnels running after you log out, and to start them at boot, the installer runs `loginctl enable-linger` for the central-host user. Without lingering, the tunnels stop at logout and the agent cannot reach the MCP servers until you log in again. If the installer cannot enable lingering, it prints a warning and continues.

The installer does not record the previous state. To find out whether lingering was on, run this command **before** the first installer run:

```bash
loginctl show-user "$USER" --property=Linger
```

To restore the state `Linger=no`:

1. Optional. Stop and disable the tunnels, so that they do not start when you log in. List them, then disable each one by name:

   ```bash
   systemctl --user list-units 'fleet-tunnel@*'
   systemctl --user disable --now fleet-tunnel@<name>
   ```

2. Disable lingering:

   ```bash
   loginctl disable-linger "$USER"
   ```

   If the command is denied, ask an administrator to run it for your user.

3. Check the result. The output must be `Linger=no`:

   ```bash
   loginctl show-user "$USER" --property=Linger
   ```

If you keep the tunnels enabled but disable lingering, they run only while you have a login session. They start again at your next login.

## Handle secrets

- Do not put secrets in `hosts.yaml` or in a chat. The inventory has variable names and configuration, not credential values.
- The installer generates missing application credentials. It sends them over SSH.
- The installer stores the MCP credentials on the central host with restricted permissions.

## Protect Docker access

Membership in the `docker` group of a node gives root-equivalent access. Use a dedicated deployment account. Protect its SSH key.
