# Benchmark Vision AI Detection Apps

This guide demonstrates how to benchmark the detection pipeline to determine
optimal stream density and performance characteristics.

## Contents

### Prerequisites

> [!NOTE]
> Set up the application by following the [Get Started Guide](../get-started.md) **only up to and including** the `./setup.sh` step (copy the `.env_<app>` file to `.env`, edit it, and run `./setup.sh`). Do **not** run `docker compose up`; the benchmark script starts and stops the application stack itself.

- Docker with the `docker compose` plugin installed
- `curl`, `jq`, `gawk`, `ffmpeg`, and `bc` utilities installed

### Benchmark Script Usage

Navigate to the `[WORKDIR]/manufacturing-ai-suite/industrial-edge-insights-vision` directory and use the benchmark script:

```bash
./calc_stream_density.sh -p <pipeline_name> [-t <target_fps>] [-i <interval>]
```

The stream count range is determined automatically: the script ramps up 1, 2, 4, 8, ... streams until the target FPS is missed, then bisects between the last passing and first failing counts to find the maximum sustainable density.

**Arguments:**

- `-p <pipeline_name>` : **(Required)** The name of the pipeline to benchmark (e.g., pallet_defect_detection or pcb_anomaly_detection)
- `-nstreams <N1> [N2 ...]` : Run the listed pipelines concurrently at fixed stream counts instead of searching (see [NStreams Mode](#nstreams-mode))
- `-t <target_fps>` : Target FPS threshold (default: 14.95)
- `-i <interval>` : Monitoring duration in seconds per test run (default: 60)
- `-c <throughput_percentile>` : Throughput percentile for KPI calculation (default: 0.9)

> **Note:** `-l` and `-u` are deprecated. They are still accepted for backward compatibility but ignored. Set `MAX_STREAMS=<n>` in the environment to raise the internal safety ceiling for the automatic search (default: 64).

### Fresh Application Stack per Round

The script manages the application lifecycle itself, so each benchmark round starts from a clean state:

- Before benchmarking, it runs `docker compose down -v` to clear any running stack.
- At the start of every round (every stream count tested, or the single NStreams run), it runs `docker compose up -d` and waits until DL Streamer Pipeline Server is ready (timeout set by the `COMPOSE_READY_TIMEOUT` environment variable, default 300 seconds).
- At the end of every round, it stops the pipelines and runs `docker compose down -v --remove-orphans`, which also removes the stack's named volumes (for example, SeaweedFS data).
- If the script is interrupted (Ctrl+C), the stack is also brought down.

### NStreams Mode

To measure a fixed, known configuration instead of searching for one, pass `-nstreams` with one stream count per pipeline, in the same order as `-p`. All pipelines start concurrently, run for the monitoring window, and report combined KPIs in `benchmark-multi/kpi.txt`.

```bash
./calc_stream_density.sh -p pallet_defect_detection_gpu pcb_anomaly_detection_gpu -nstreams 6 4 -t 28.5 -i 60
```

### Configuration

The benchmark script automatically uses the configured sample application and its payload file:

1. **Application Selection**: The script reads `SAMPLE_APP` from the `.env` file to determine which application to benchmark
2. **Payload Configuration**: Uses the standard `payload.json` file from the selected application directory (`apps/${SAMPLE_APP}/payload.json`)
3. **Pipeline Selection**: Choose from available pipelines in the payload file:


- **`pallet_defect_detection`**: CPU-based detection pipeline
- **`pallet_defect_detection_gpu`**: GPU-accelerated detection pipeline with optimized settings
- **`pcb_anomaly_detection`**: CPU-based anomaly classification pipeline
- **`pcb_anomaly_detection_gpu`**: GPU-accelerated anomaly classification pipeline with optimized settings

### Recommended Pipeline Parameters

These are the recommended parameters by Edge Benchmarking and Workloads team for workload with similar characteristics. These are configurable parameters that can be adjusted based on your specific requirements:

```text
inference-region=full-frame inference-interval=1 batch-size=8 nireq=2 ie-config="GPU_THROUGHPUT_STREAMS=2" threshold=0.7
```

**Parameter Descriptions:**

- `inference-region=full-frame`: Process the entire frame for detection
- `inference-interval=1`: Run inference on every frame
- `batch-size=8`: Process 8 frames in a single batch for better GPU utilization
- `nireq=2`: Number of inference requests to run in parallel
- `ie-config="GPU_THROUGHPUT_STREAMS=2"`: OpenVINO™ engine streams configuration
- `threshold=0.7`: (recommended for Pallet Defect Detection) Detection confidence threshold (70%)

### Steps to run benchmarks

<!--hide_directive ::::{tab-set} hide_directive-->
<!--hide_directive :::{tab-item} hide_directive-->**Pallet Defect Detection**
<!--hide_directive :sync: pallet-detect hide_directive-->

1. **Set up the environment**: Run `cp .env_pallet-defect-detection .env` (ensures `SAMPLE_APP=pallet-defect-detection`), edit `.env`, and run `./setup.sh`. Do not run `docker compose up`.

2. **Test CPU performance**:

   ```bash
   ./calc_stream_density.sh -p pallet_defect_detection -t 25.0 -i 30
   ```

3. **Test GPU performance** (if available):

   ```bash
   ./calc_stream_density.sh -p pallet_defect_detection_gpu -t 28.5 -i 60
   ```

   > [!NOTE]
   > The script automatically uses the `payload.json` file from the configured sample application directory.

<!--hide_directive ::: hide_directive-->
<!--hide_directive :::{tab-item} hide_directive--> **PCB Anomaly Detection**
<!--hide_directive :sync: pcb-detect hide_directive-->

1. **Set up the environment**: Run `cp .env_pcb-anomaly-detection .env` (ensures `SAMPLE_APP=pcb-anomaly-detection`), edit `.env`, and run `./setup.sh`. Do not run `docker compose up`.

2. **Test CPU performance**:

   ```bash
   ./calc_stream_density.sh -p pcb_anomaly_detection -t 25.0 -i 30
   ```

3. **Test GPU performance** (if available):

   ```bash
   ./calc_stream_density.sh -p pcb_anomaly_detection_gpu -t 28.5 -i 60
   ```

   > [!NOTE]
   > The script automatically uses the `payload.json` file from the configured sample application directory.

<!--hide_directive
:::
::::
hide_directive-->

### Understand the Results

The benchmark uses binary search to find optimal stream density. Key metrics include:

- **Stream Density**: Maximum concurrent streams achieving target FPS
- **Throughput Median**: Median FPS across all streams
- **Throughput Cumulative**: Total FPS sum of all streams

**Sample Output:**

```text
streams: 6 throughput: 28.8 range: [5,7]
======================================================
✅ FINAL RESULT: Stream-Density Benchmark Completed!
stream density: 6
======================================================
throughput median: 29.0
throughput cumulative: 173.8
```

### Troubleshooting

**Common Issues:**

1. **DL Streamer Pipeline Server Not Reachable After Startup**

   ```text
   >>>>> Waiting for DL Streamer Pipeline Server to become ready... timed out after 300s.
   ```

   - The script starts the stack itself; check container logs: `docker compose logs dlstreamer-pipeline-server`
   - Ensure `./setup.sh` completed successfully and `.env` is configured
   - On slow systems, increase the wait: `COMPOSE_READY_TIMEOUT=600 ./calc_stream_density.sh ...`
   - If the script was terminated abnormally (e.g., `kill -9`), bring the stack down manually: `docker compose down -v --remove-orphans`

2. **Pipeline Startup Failures**
   - Check model file paths in `payload.json`
   - Verify video file accessibility
   - Monitor system resources (CPU, memory, GPU)
   - Ensure the correct SAMPLE_APP is set in .env file

3. **Pipeline Not Found**

   ```text
   Error: Pipeline 'pipeline_name' not found in payload.json
   ```

   - Verify the pipeline name exists in `apps/${SAMPLE_APP}/payload.json`
   - Check available pipelines: `jq '.[].pipeline' apps/${SAMPLE_APP}/payload.json`

4. **Debug Mode**
   Add `--trace` to see detailed execution steps:

   <!--hide_directive::::{tab-set} hide_directive-->
   <!--hide_directive:::{tab-item} hide_directive-->**Pallet Defect Detection**
   <!--hide_directive :sync: pallet-detect hide_directive-->

   ```bash
   ./calc_stream_density.sh -p pallet_defect_detection_gpu --trace
   ```

   <!--hide_directive ::: hide_directive-->
   <!--hide_directive :::{tab-item} hide_directive--> **PCB Anomaly Detection**
   <!--hide_directive :sync: pcb-detect hide_directive-->

   ```bash
   ./calc_stream_density.sh -p pcb_anomaly_detection_gpu --trace
   ```

   <!--hide_directive
   :::
   ::::
   hide_directive-->
