# Redeploy and Handle Credentials

- **Recipe deployments replace their managed checkout.** Local `.env` values, downloaded models, and edits inside that checkout can be deleted during a normal deployment. Back up anything that must be retained and be ready to restore manually supplied secrets.
- **Use `--no-deploy` when the app is already running** and you need to prepare the Hermes connection without redeployment. It preserves the managed checkout, but still performs node and profile preparation and MCP registration.
- **Keep secrets out of `hosts.yaml` and chat.** The inventory contains variable names and configuration, not credential values. The installer generates missing app credentials and transfers them over SSH; MCP credentials are stored on the central host with restricted permissions.
- **Treat Docker access as privileged.** Membership in the node's `docker` group is root-equivalent. Use a dedicated deployment account and protect its SSH key.
