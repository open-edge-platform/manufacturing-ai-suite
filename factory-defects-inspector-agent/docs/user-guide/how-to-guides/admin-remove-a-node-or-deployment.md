# Remove a Node or Deployment

Use this guide to decommission a node or a deployment. The work has two parts:

1. **Automated.** The installer removes the state that it created on the central Hermes host.
   This is safe to repeat, and a new installer run recreates it.
2. **Manual.** You clean up the edge node and the shared parts of the central host. These steps
   delete data or affect other software, so the installer never does them.

> [!CAUTION]
> Run the automated step **before** you remove the node from `hosts.yaml`. The installer finds
> what to remove from the inventory. Remove the inventory entry only at the end. If you keep
> it, the next installer run deploys the node again.

## Automated: remove the central-host state

This step never connects to a node. It does not stop applications, delete files on a node, or
change SSH keys.

For each selected deployment, it removes:

| Item | Location |
| --- | --- |
| The SSH tunnel | The `fleet-tunnel@<name>` user service and `~/.config/fleet-tunnels/<name>.env` |
| The MCP registration | The `mcp_servers.<name>` entry in the default Hermes profile |
| The node profile | The Hermes profile of the deployment |
| The stored MCP credential | `<NAME>_MCP_BASIC` or `<NAME>_MCP_TOKEN` in `~/.hermes/.env` |
| The pinned certificate and the deployment log | `~/.hermes/certs/<name>.pem` and `~/.hermes/logs/fleet/<name>.deploy.log` |

It does not touch the default profile, the model configuration, the persona, other
deployments, or the WebUI.

1. Select the deployment. Without `--node` and `--recipe`, the command applies to every
   deployment in the inventory.

   **central Hermes host**

   ```bash
   ./fleet-setup.sh --teardown --node node1
   ```

   The output lists each step with `PLAN:`. It then asks for confirmation. The command needs
   an interactive terminal.

2. Read the plan. Make sure that it names only the deployments that you want to remove.
   Answer `n` to cancel. Nothing changes.

3. Answer `y` to apply the plan.

4. Check the result:

   **central Hermes host**

   ```bash
   systemctl --user list-units 'fleet-tunnel@*'
   hermes profile list
   ```

   The tunnel and the profile of the removed deployment must not be listed.

## Manual: clean up the edge node

Do these steps in order. The installer leaves all of this in place on purpose.

1. **Back up what you must keep.** The application checkout contains the `.env` file with the
   generated credentials, downloaded models, data volumes, and your local edits. Deleting the
   checkout removes them.

2. **Stop the application.** Run the stop command of the application in its directory. For the
   multimodal application, use `make down`. Do not remove the Docker volumes unless you are
   sure that you do not need the data. Volumes hold the time-series, model, and media data.

   **edge node**

   ```bash
   cd ~/fleet-deployments/<deployment-name>/checkout/<app-directory>
   make down
   docker ps
   ```

   `docker ps` must not list containers of the application.

3. **Delete the checkout.** Review the content first. The checkout is under
   `~/fleet-deployments/<deployment-name>/`.

   **edge node**

   ```bash
   ls -la ~/fleet-deployments/<deployment-name>/
   rm -rf ~/fleet-deployments/<deployment-name>
   ```

   If `rm` reports `Permission denied`, containers created files that another user owns. Ask
   an administrator to remove them after you confirm the path. Do not use a wildcard or a
   path outside the deployment directory.

   A deployment that uses `app_path` is managed outside the installer. Do not delete its
   directory unless you own it.

4. **Remove unused Docker images and volumes.** Docker resources can be shared with other
   workloads. List them and remove only the ones that belong to the application. Do not run
   `docker system prune` on a shared node.

   **edge node**

   ```bash
   docker images
   docker volume ls
   ```

5. **Remove the central host key.** The installer added the public key of the central host to
   `~/.ssh/authorized_keys` of the node user. Find the key by its comment, which is the
   `user@host` of the central host, or `fleet-setup@<host>` for a key that the installer
   created. Then delete only that line with an editor. Skip this step if the central host
   must keep access.

   **edge node**

   ```bash
   grep -n '<key-comment>' ~/.ssh/authorized_keys
   ```

6. **Rotate the credentials if the node stays in use.** The application credentials were stored
   in the checkout `.env` file and on the central host. After the removal of the central
   state, the central host no longer has them. Rotate them if you reuse the application, or
   if the node leaves your control.

7. **Leave the packages and the Docker group alone.** The installer can add `make`, `curl`,
   `git`, Docker Engine, and Docker Compose, and add the user to the `docker` group. Other
   software can depend on them.

## Manual: clean up the central host

1. **Remove the node from the SSH known hosts.**

   **central Hermes host**

   ```bash
   ssh-keygen -R <node-host>
   ```

2. **Remove a dedicated SSH key.** Do this only if the inventory has an `identity_file` that
   was used for this node alone, and nothing else uses it. The default key,
   `~/.ssh/id_ed25519`, can be in use elsewhere. Keep it.

3. **Restore user lingering.** After you remove the last tunnel, decide whether the central
   user needs lingering. See [Restore user lingering](./admin-redeploy-and-handle-credentials.md#restore-user-lingering).

4. **Review the Hermes chat history.** The chats of the default profile can mention the
   node and its data. Keep or delete them, according to your records policy.

5. **Remove the cached skill checkout.** *Optional.* The cache at `~/.cache/fleet-setup/` is
   safe to delete. A later installer run downloads it again.

## Finish

Remove the node, or the deployment, from `hosts.yaml`. Then run `./fleet-setup.sh --list` to
check that the inventory is valid and no longer names it.

**central Hermes host**

```bash
./fleet-setup.sh --list
```
