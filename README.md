# Manufacturing AI Suite

Manufacturing AI Suite is a curated and open set of software solutions intended to demonstrate
the applicability and efficiency of Intel hardware in industry-specific edge AI use cases.

The suite simplifies building, deploying, and scaling custom real time edge AI solutions for
industrial environments by providing AI acceleration tools, support for IoT protocols (MQTT/OPC UA),
accelerated analytics libraries, multi camera system software, and reusable sample applications,
frameworks, microservices, and benchmarks.

It includes:

- Tools for AI acceleration (for example, MQTT/OPC UA support, analytics libraries, camera system software)
- A complete AI pipeline for closed-loop systems
- Benchmarking support for evaluating performance across time series, vision, and generative AI workloads

**Manufacturing AI Suite** helps you develop solutions for:

- **Production Workflow**: Detect defects, optimize efficiency
- **Safety**: AI-driven risk reduction
- **Real-Time Insights**: Local data processing, trend tracking
- **Automation**: Instant alerts and corrective actions

**Sample Applications**

|              |             |            |
|:-------------|:------------|:-----------|
| [HMI Augmented worker](./hmi-augmented-worker/)                                           | A RAG-enabled HMI application deployable on type-2 hypervisors.                                 | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/hmi-augmented-worker/index.html)                                                          |
| [Pallet Defect Detection](./industrial-edge-insights-vision/apps/pallet-defect-detection) | Real-time pallet condition monitoring via multiple AI models.                                   | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-vision/pallet-defect-detection/index.html)                       |
| [PCB Anomaly Detection](./industrial-edge-insights-vision/apps/pcb-anomaly-detection)     | Real-time anomaly detection in printed circuit boards (PCB) with AI vision systems.             | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-vision/pcb-anomaly-detection/index.html)                         |
| [Win Vision AI](./industrial-edge-insights-vision/win-vision-ai/) | A Windows application for running any Vision workloads on DL Streamer-supported models.                     | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-vision/win-vision-ai/index.html)                  |
| [Wind Turbine Anomaly Detection](./industrial-edge-insights-time-series/apps/wind-turbine-anomaly-detection) | A time series use case of detecting anomalous power generation patterns relative to wind speed. | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-time-series/index.html) |
| [Multimodal Weld Defect Detection](./industrial-edge-insights-multimodal/) | A multimodal use case combining vision and sensor data analysis to identify anomalies in welding data. | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/industrial-edge-insights-multimodal/index.html) |
| [Factory Defects Inspector Agent](./factory-defects-inspector-agent/) | A Hermes agent that investigates defects and anomalies reported by manufacturing applications on remote edge nodes. | [Documentation](https://docs.openedgeplatform.intel.com/dev/edge-ai-suites/ai-suite-manufacturing/factory-defects-inspector-agent/index.html) |

**Main tools and AI Libraries the Suite uses**

|              |             |
|:-------------|:------------|
| [Deep Learning Streamer](https://github.com/open-edge-platform/dlstreamer/tree/main)                                     | A framework for building optimized media analytics pipelines powered by OpenVINO&trade; toolkit.                                 |
| [Deep Learning Streamer Pipeline Server](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/microservices/dlstreamer-pipeline-server)  | A containerized microservice, built on top of GStreamer, for development and deployment of video analytics pipelines.            |
| [Model Download](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/microservices/model-download)                                      | Providing capabilities to download AI models so that they can be seamlessly used for inferencing with DL Streamer and DL Streamer Pipeline Server.                                                                   |
| [Time Series Analytics Microservice](https://github.com/open-edge-platform/edge-ai-libraries/tree/main/microservices/time-series-analytics)           | Built on top of **Kapacitor**, a containerized microservice for development and deployment of time series analytics capabilities |
| [Intel&reg; Geti&trade; SDK](https://github.com/open-edge-platform/geti-sdk)                                                                          | A python package containing tools to interact with a Geti&trade; server via the REST API, helping you build a full MLOps for vision based use cases. |
| [OpenVINO&trade; toolkit](https://github.com/openvinotoolkit/openvino)                                                                                | An open source toolkit for deploying performant AI solutions across Intel hardware for generative and conventional AI models.    |
| [OpenVINO&trade; Model Server](https://github.com/openvinotoolkit/model_server)                                                                       | An OpenVINO server solution for enabling remote model inference for AI applications deployed on low-performance devices.         |

## Skills

This repository ships [Agent Skills](https://agentskills.io) that let AI coding assistants
(GitHub Copilot, Claude Code, Codex and other compatible agents) build, deploy, validate and review
the applications in this suite. Suite-level skills live in [`.github/skills/`](.github/skills/) and
are discovered automatically; app-level skills live in the `.github/skills/` folder of each
application and are indexed by its `skill-catalog.json`.

### Suite-level skills

| Skill | Description |
|-------|-------------|
| [manufacturing-ai-app-builder](.github/skills/manufacturing-ai-app-builder/SKILL.md) | Conversational orchestrator that turns a plain manufacturing-quality business objective into a working Intel Edge AI application by asking only business questions, proposing a plan, and delegating the build to the right skills. |
| [manufacturing-app-recipe](.github/skills/manufacturing-app-recipe/SKILL.md) | Stands up a complete, ready-to-run manufacturing analytics stack (vision, time series, multimodal, with optional VLM narrative and agentic orchestration) with one Docker Compose command. |
| [onboarding-validation](.github/skills/onboarding-validation/SKILL.md) | Validates the get-started experience of Open Edge Platform components by following the documented path exactly and producing a structured pass/fail report. |
| [security-review](.github/skills/security-review/SKILL.md) | On-demand security review for code, containers, Docker Compose, Helm/Kubernetes configuration and CI/CD workflows. |

To start from a business goal, such as "alert me before a pump fails", copy a ready-made prompt from
[`skills/prompts/`](skills/prompts/) into your AI agent. Each prompt hands off to
`manufacturing-ai-app-builder`. For details, see the
[Manufacturing Application Builder guide](skills/docs/user-guide/index.md).

### Application skills

| Skill | Application | Description |
|-------|-------------|-------------|
| [multimodal-deploy](industrial-edge-insights-multimodal/.github/skills/multimodal-deploy/SKILL.md) | [Industrial Edge Insights - Multimodal](industrial-edge-insights-multimodal/) | Build, deploy, smoke-check and functionally test the Multimodal Weld Defect Detection application, including the vLLM, agentic and MCP variants. |
| [time-series-deploy](industrial-edge-insights-time-series/.github/skills/time-series-deploy/SKILL.md) | [Industrial Edge Insights - Time Series](industrial-edge-insights-time-series/) | Build, deploy, smoke-check and functionally test the Time Series sample applications (for example wind turbine anomaly detection) with MQTT or OPC-UA ingestion. |

## Contribute

Read the [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting issues and pull requests.

## Community and Support

For support, submit your bug report and feature request to [Github Issues](https://github.com/open-edge-platform/manufacturing-ai-suite/issues).

## License

The **Manufacturing AI Suite** project is licensed under the [APACHE 2.0](LICENSE).  

## Intended Use

Applications developed in this repository, unless stated otherwise, are intended for reference
and demonstration purposes, not for production environments.
Certain features, such as authentication, TLS termination, and external access controls are
assumed to be covered at the infrastructure level.

For more information, refer to the
[Notes on Usage](https://docs.openedgeplatform.intel.com/dev/OEP-articles/notes-on-usage.html)
document.
