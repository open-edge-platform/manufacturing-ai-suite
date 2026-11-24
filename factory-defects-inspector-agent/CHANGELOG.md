# Changelog

All notable changes to this project are documented in this file.

## [2026.3] - December 2026

### Added
- Added a Hermes-based fleet orchestrator to prepare remote edge nodes, deploy selected manufacturing applications and MCP servers, and register them with the central Hermes instance through SSH tunnels with pinned TLS certificates. ([#38])
- Added YAML inventory planning for multi-node, multi-recipe deployments, including preflight validation and targeted or no-deploy setup options. ([#38])
- Added a reusable Hermes persona, an optional WebUI management script, and administrator/operator guides for setup, deployment, and investigation workflows. ([#38])
- Added an agent-harness adapter layer for fleet deployment, with Hermes remaining the default harness. ([#51])
- Added inventory-scoped teardown that removes selected deployment state from the central host after confirmation, without contacting edge nodes. ([#91])

### Changed
- Simplified Hermes WebUI management to start and stop commands, preserved existing personas, and added self-signed HTTPS. ([#51], [#91])
- Updated the weld and wind-turbine deployment recipes to use the official repository. ([#46])

### Fixed
- Fixed fleet redeployment failures by checking whether Hermes profiles were actually removed and using a shorter temporary directory for SSH sockets. ([#76])
- Fixed false credential validation failures caused by masked output and reported missing recipe prompts or policies before starting deployment. ([#76])

### Documentation
- Updated administrator and operator guides for setup, user-service persistence, model license review, fleet deployment, and removal. ([#61], [#71], [#73], [#77], [#91])
- Reorganized system requirements and raised the central Hermes host's documented minimum RAM from 32 GB to 48 GB for the supplied agentic weld deployment recipe. ([#78], [#91], [#108])
- Updated clone instructions, release links, and third-party notices. ([#52], [#83], [#86], [#88], [#92])

---
[#38]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/38
[#46]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/46
[#51]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/51
[#52]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/52
[#61]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/61
[#71]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/71
[#73]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/73
[#76]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/76
[#77]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/77
[#78]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/78
[#83]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/83
[#86]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/86
[#88]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/88
[#91]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/91
[#92]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/92
[#108]: https://github.com/open-edge-platform/manufacturing-ai-suite/pull/108
