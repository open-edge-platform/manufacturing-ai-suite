# Example prompt: quick MQTT Docker Compose deploy + smoke test

> Quickly build and deploy the wind turbine anomaly detection app with MQTT
> ingestion via Docker Compose, then run a smoke test and report whether
> it's healthy.

Expected agent flow:
1. Resolve app root, check `.env`, run Docker preflight.
2. `make build`
3. `make up_mqtt_ingestion app=wind-turbine-anomaly-detection`
4. `.github/skills/time-series-deploy/scripts/smoke-check.sh`
5. Report real command output and a clear PASS/FAIL summary.
6. Offer `make down` for cleanup.
