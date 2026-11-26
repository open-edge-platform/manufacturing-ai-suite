## Functional Test Steps

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

   ```sh
   pytest -v -s --html=docker_multimodal_report.html test_docker_deployment_multimodal.py
   ```

3. To run the `make up_vllm` and `make up_agentic` deployment tests:

   > [!NOTE]
   > These tests require an Intel Panther Lake system and are skipped unless
   > `RUN_MULTIMODAL_VLLM_AGENTIC_TESTS=true` is set.

   ```sh
   RUN_MULTIMODAL_VLLM_AGENTIC_TESTS=true pytest -s test_docker_deployment_agentic_vllm.py
   ```
