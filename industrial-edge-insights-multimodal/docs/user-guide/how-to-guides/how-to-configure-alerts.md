# Configure Alerts

This section provides instructions for setting up alerts in **Time Series Analytics Microservice**.

## Publish MQTT Alerts

#### Configure MQTT Alerts

By default, the following MQTT alerts are configured in the
[`configs/time-series-analytics-microservice/config.json`](https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/industrial-edge-insights-multimodal/configs/time-series-analytics-microservice/config.json)
file (see the `alerts` section).

#### Configure MQTT Alert in TICK Script

The MQTT alert is configured by default in the TICK script. Refer to
[`configs/time-series-analytics-microservice/tick_scripts/weld_anomaly_detector.tick`](https://github.com/open-edge-platform/manufacturing-ai-suite/blob/main/industrial-edge-insights-multimodal/configs/time-series-analytics-microservice/tick_scripts/weld_anomaly_detector.tick)
for the `alert()` block details.

> [!NOTE]
> Setting **QoS** to `1` ensures messages are delivered at least once. Alerts are preserved and resent if the MQTT broker reconnects after downtime.

## Subscribe to MQTT Alerts

Follow the steps to subscribe to the published MQTT alerts.

To subscribe to all MQTT topics, execute the following command:

```sh
docker exec -ti ia-mqtt-broker mosquitto_sub -h localhost -v -t '#' -p 1883
```

### Subscribing to Time Series Analytics Microservice Alerts

```sh
docker exec -ti ia-mqtt-broker mosquitto_sub -h localhost -v -t alerts/weld_defect_detection -p 1883
```

### Subscribing to DL Streamer Pipeline Server Results

```sh
docker exec -ti ia-mqtt-broker mosquitto_sub -h localhost -v -t vision_weld_defect_classification -p 1883
```

### Subscribing to Fusion Analytics Results

```sh
docker exec -ti ia-mqtt-broker mosquitto_sub -h localhost -v -t fusion/anomaly_detection_results -p 1883
```

## Supporting Resources

- [Kapacitor MQTT Alert Documentation](https://docs.influxdata.com/kapacitor/v1/reference/event_handlers/mqtt/).
