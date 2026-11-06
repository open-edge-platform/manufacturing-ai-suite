
# System Requirements

This page provides detailed hardware, software, and platform requirements to help you set up and run the application efficiently.

For quick deployment of hardware components, you can use
[Edge Developer Kit Reference Scripts](https://github.com/open-edge-platform/edge-developer-kit-reference-scripts)
provided as part of Open Edge Platform.

## Minimum Requirements

> [!NOTE]
> The requirements below are for the default deployment described in the [Get Started](../get-started.md) guide.
> For optional deployments, see the hardware requirements in the [vLLM service](../how-to-guides/how-to-deploy-vllm-service.md) and [agentic workflow](../how-to-guides/how-to-deploy-agent-workflow.md) deployment guides.

| Component           | Specification                                                                                   |
|---------------------|-------------------------------------------------------------------------------------------------|
| **Processor**       | 13th Gen Intel® Core™ or Intel® Xeon® processor                                                 |
| **RAM**             | Minimum 16 GB                                                                                   |
| **Storage**         | Minimum 64 GB (128 GB recommended)                                                              |

## Software Requirements

**Required Software**:

- Operating System Ubuntu 24.04/Ubuntu 26.04
- Docker 24.0.7 or higher
- Python 3.10+

## Validated Platforms

| Product / Family                            | CPU | iGPU | NPU |
|---------------------------------------------|-----|------|-----|
| Intel® Core™ Ultra Processors (Series 3, 2) | ✓   | ✓    | ✓   |
| Intel® Core™ Processors (13th Gen)          | ✓   | ✓    | N/A |

## Validation

Ensure all required software are installed and configured before proceeding to [Get Started](../get-started.md).
