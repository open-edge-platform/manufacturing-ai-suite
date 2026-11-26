# Release Notes: Factory Defects Inspector Agent

## Version 2026.3

**Release Date**: December 7, 2026

This initial release introduces **Hermes-based fleet deployment**, **Model Context Protocol (MCP) access to remote manufacturing applications**,
and **operator workflows for investigating defects across edge nodes**, alongside a reusable
persona and optional WebUI.

**New**:

- **Fleet deployment**: added an installer to prepare edge nodes and deploy selected manufacturing applications across a configured fleet.
- **Inventory planning**: added YAML-based multi-node, multi-application configuration with preflight validation and options for targeted setup.
- **MCP registration**: added SSH tunnels with pinned TLS certificates to connect edge-node MCP servers to central Hermes.
- **Operator workflows**: added a reusable Hermes persona and optional WebUI for investigating defects and anomalies. The agent supports human decisions; it does not make final pass/fail calls or act as a safety interlock.
- **Fleet teardown**: added a confirmation step for removing selected deployment state from the central host without contacting or changing edge nodes.
- **Hermes WebUI management**: added start and stop controls with self-signed HTTPS while preserving existing personas.
- **Deployment validation**: added pre-deployment checks for credentials, recipe prompts, and policies.
