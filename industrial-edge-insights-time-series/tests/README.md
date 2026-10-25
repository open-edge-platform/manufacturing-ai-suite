# Tests

## MCP server tests

Run these commands from the component root:

```bash
python3 -m venv /tmp/time-series-mcp-tests
/tmp/time-series-mcp-tests/bin/pip install \
  -r mcp-server/requirements.txt pytest==8.4.2 pytest-asyncio==1.2.0
/tmp/time-series-mcp-tests/bin/pytest tests/mcp -q \
  -o asyncio_mode=auto -o asyncio_default_fixture_loop_scope=function
```

Unit tests use mocked upstream services and test-only credentials.
Compose tests validate configuration without starting the application.
Enable the query-contract integration test with `RUN_MCP_DOCKER_TESTS=1`.
It creates and removes a uniquely named InfluxDB container with a loopback-only random port.
It does not use the deployment's environment file or change existing containers.

```bash
RUN_MCP_DOCKER_TESTS=1 /tmp/time-series-mcp-tests/bin/pytest tests/mcp -q \
  -o asyncio_mode=auto -o asyncio_default_fixture_loop_scope=function
```

For real HTTPS, UDF output, stream/batch start, stop, and restart tests:

```bash
docker build -t industrial-edge-insights-time-series-mcp:2026.1.0 mcp-server
RUN_MCP_STACK_TESTS=1 /tmp/time-series-mcp-tests/bin/pytest tests/mcp/test_lifecycle.py -q \
  -o asyncio_mode=auto -o asyncio_default_fixture_loop_scope=function
```

These tests use private Compose projects and loopback-only random ports.
They use pinned analytics, MQTT, InfluxDB, nginx, and local MCP images.
They generate credentials, trust the generated gateway certificate, and always remove their containers and volumes.
The stream test sends a sensor point and checks the real UDF result.
The batch test checks lifecycle operations without waiting for the 20-minute processing window.
They do not deploy Telegraf, physical devices, or the Grafana dashboard.

## Existing functional tests

1. Install test dependencies:

    ```sh
    cd ./tests/functional/
    python3 -m venv env
    source env/bin/activate
    pip3 install -r ../requirements.txt
    ```

2. For Docker-related test cases, run the following commands:

   > [!NOTE]
   > Docker and Docker Compose must be installed as prerequisites.

   * Wind Turbine Anomaly Detection

      ```sh
      pytest -v -s --html=docker_wind_turbine_report.html test_docker_deployment_wind_turbine.py

      # InfluxDB retention test
      pytest -v -s --html=docker_influxdb_retention_wind_turbine_report.html test_docker_influxdb_retention.py

      # Stability test
      pytest -v -s --html=docker_stability_wind_turbine_report.html test_docker_deployment_stability.py
      ```

3. Security tests:

    ```sh
    pytest -v -s --html=report.html test_docker_deployment_security.py
    ```