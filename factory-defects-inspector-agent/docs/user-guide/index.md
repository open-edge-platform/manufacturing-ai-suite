```{eval-rst}
.. meta::
   :description: A Hermes agent that investigates defects and anomalies reported by
      manufacturing applications on remote edge nodes.
```

# Factory Defects Inspector Agent

The Factory Defects Inspector Agent is a [Hermes Agent](https://github.com/NousResearch/hermes-agent) on a central host that helps people investigate defects and anomalies reported by manufacturing applications on remote edge nodes, such as weld defect detection and wind-turbine anomaly detection. It supports human inspection and decisions; it is not a safety interlock and does not make final pass/fail calls.

The installer (`fleet-setup.sh`) sets the agent up. It uses deployment skills to prepare and deploy the applications, exposes each node's MCP server through an SSH tunnel, and registers the servers with Hermes. These "fleet" scripts and settings manage nodes and deployments; inspection happens afterward through Hermes chat.

This guide helps two audiences:

- **Administrator:** prepares the central host and edge nodes, configures the inventory, and runs the setup. See [Get Started](./get-started.md).
- **Operator:** after setup, asks Hermes to inspect or operate the registered nodes in natural language. See [Use Hermes as an Operator](./how-to-guides/use-hermes.md).

## What the installer sets up

For each deployment in the inventory, the installer can:

1. Create a Hermes profile configured to run the deployment skill's commands on the node over SSH.
2. Prepare the node and deploy the selected manufacturing application and its MCP server.
3. Establish a local SSH tunnel to the node's MCP endpoint, retrieve and pin its TLS certificate, and register the MCP server with Hermes.

After setup, an operator can start a new Hermes session and ask about the registered nodes. For example:

> Describe node1 and node2, then summarize their status.

The available nodes, skills, prompts, and MCP tools depend on the configured inventory.

<!--hide_directive
:::{toctree}
:hidden:

how-it-works.md
get-started.md
how-to-guides.md
release-notes.md

:::
hide_directive-->
