# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Functional test map — industrial-edge-insights-time-series

All files live in `tests/functional/`. Install deps first:

```bash
cd tests/functional
python3 -m venv env && source env/bin/activate
pip3 install -r ../requirements.txt
```

| File | Deployment method | Scenario |
|---|---|---|
| `test_docker_deployment_wind_turbine.py` | Docker Compose | Primary functional deploy test (tests marked `mqtt`/`opcua`, some `kpi`) |
| `test_docker_influxdb_retention.py` | Docker Compose | Marked `longrun`; InfluxDB retention policy check |
| `test_docker_deployment_stability.py` | Docker Compose | Marked `longrun`; extended stability run |
| `test_GPU_docker.py` | Docker Compose | Marked `gpu`; skipped when no GPU device is detected |
| `test_docker_deployment_security.py` | Docker Compose | Marked `docker_security`; compose file integrity, nmap open ports, InfluxDB/Grafana auth, credential leakage in logs |

Shared fixtures live in `conftest_docker.py`. The `setup_docker_environment`
fixture writes generated valid credentials into `.env` and runs `make down`
after each test. Back up `.env` first if the user's values must be preserved.

Markers available (see `pytest.ini`): `kpi`, `mqtt`, `opcua`,
`docker_security`, `longrun`, `gpu`. Example: select only MQTT-path tests with
`pytest -v -s -m mqtt`.

Reports: pass `--html=<name>.html` to get an HTML report; always summarize
PASS/FAIL counts from the pytest console output in your answer, don't just
point at the report file.
