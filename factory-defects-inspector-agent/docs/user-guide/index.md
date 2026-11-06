```{eval-rst}
.. meta::
   :description: A Hermes agent that investigates defects and anomalies reported by
      manufacturing applications on remote edge nodes.
```

# Factory Defects Inspector Agent

<!--hide_directive
<div class="component_card_widget">
  <a class="icon_github" href="https://github.com/open-edge-platform/manufacturing-ai-suite/tree/main/factory-defects-inspector-agent">
     GitHub
  </a>
  <a class="icon_document" href="https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/factory-defects-inspector-agent/README.md">
     Readme
  </a>
</div>
hide_directive-->

The Factory Defects Inspector Agent is a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
on a central host. It helps investigate defects and anomalies that manufacturing applications
report on remote edge nodes. Examples are weld defect detection and wind-turbine anomaly detection.

> [!IMPORTANT]
> The agent supports human decisions. It is not a safety interlock. It does not make final pass or fail decisions.

## Who uses this guide

| Role | Task | Start here |
| --- | --- | --- |
| Administrator | Prepare the central host and edge nodes, then run the installer. | [Get Started](./get-started.md) |
| Operator | Ask Hermes about the registered nodes in natural language. | [Use Hermes as an Operator](./how-to-guides/use-hermes-as-operator.md) |

![Administrator and operator flows](./_assets/fdi-admin-operator-flows.drawio.svg)

## What the installer does

The installer is the `fleet-setup.sh` script. For each deployment in the inventory, it does these tasks:

1. Creates a Hermes profile that runs commands on the node over SSH.
2. Prepares the node. Deploys the manufacturing application and its MCP server.
3. Opens an SSH tunnel to the MCP server of the node.
4. Pins the TLS certificate of the MCP server.
5. Registers the MCP server with Hermes.

After setup, the operator starts a new Hermes session. Example request:

```text
Describe node1 and node2, then summarize their status.
```

The inventory defines the available nodes, skills, prompts, and MCP tools.

## See Also

- [Weld Defect Detection](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/weld-defect-detection/index.html)
- [Wind Turbine Anomaly Detection](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/wind-turbine-anomaly-detection/index.html)

<!--hide_directive
:::{toctree}
:hidden:

get-started.md
how-to-guides.md
Release Notes <./release-notes.md>

:::
hide_directive-->
