# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Functional test map — industrial-edge-insights-multimodal

All files live in `tests/functional/`. Install deps first:

```bash
cd tests/functional
python3 -m venv env && source env/bin/activate
pip3 install -r ../requirements.txt
```

| File | Deployment method | Hardware | Notes |
|---|---|---|---|
| `test_docker_deployment_multimodal.py` | Docker Compose | CPU | Primary functional deploy test (env validation, `make up`/`down`, data flow) |
| `test_GPU_docker_multimodal.py` | Docker Compose | GPU | Marked `gpu`; requires `/dev/dri` |
| `test_NPU_docker_multimodal.py` | Docker Compose | NPU | Requires `/dev/accel` |

`pytest.ini` adds the time-series test utilities
(`../../../industrial-edge-insights-time-series/tests/...`) to `pythonpath`, so
the sibling `industrial-edge-insights-time-series/tests` directory must be
present. The Get Started sparse checkout omits it; add it from the
repository root with
`git sparse-checkout add industrial-edge-insights-time-series/tests`.

The tests overwrite `.env`: credentials are replaced with generated values
and `HOST_IP` is set to the system IP address. Back up `.env` first if the
user's values must be preserved.

Markers available (see `pytest.ini`): `kpi`, `docker_security`, `longrun`,
`gpu`. Example selective run: `pytest -v -s -m gpu test_GPU_docker_multimodal.py`.

No functional test covers `make up_agentic MCP=true` or the MCP server.
Use `scripts/smoke-check.sh` (MCP `tools/list` probe) and the
`mcp-server/example/` client to verify MCP mode.

Reports: pass `--html=<name>.html` to get an HTML report; always summarize
PASS/FAIL counts from the pytest console output in your answer, don't just
point at the report file.
