#
# Apache v2 license
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#

import pytest
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../utils')))
import docker_utils
import security_utils
import constants
import time
import logging
import asyncio
from common_utils import assert_condition
import common_utils


# Set up logger
logger = logging.getLogger(__name__)

pytest_plugins = ["conftest_docker"]

# Docker environment variables
docker_wait_time, docker_target, docker_grafana_port, docker_mqtt_port, docker_opcua_port = docker_utils.get_docker_env_values()
DOCKER_PROXY_URL = os.getenv("DOCKER_PROXY_URL", None)

@pytest.mark.docker_security
def test_docker_file_integrity():
    logger.info("TC_005: Verify docker-compose file integrity in the system.")
    docker_file_integrity_result = security_utils.verify_docker_file_integrity()
    logger.info(f"verify_docker_file_integrity result: {docker_file_integrity_result}")
    assert_condition(docker_file_integrity_result == True, "Docker-compose file integrity verification failed.")

@pytest.mark.docker_security   
def test_nmap_open_ports_opcua_docker(setup_docker_environment):
    logger.info("TC_006: Verify nmap open ports functionality with opcua using Docker.")
    
    # Access the context from setup_docker_environment fixture
    context = setup_docker_environment
    
    # Deploy and verify Docker containers with OPC-UA ingestion (includes nmap scan)
    results = docker_utils.deploy_and_verify(context, deploy_type="opcua", include_nmap=True)
    
    logger.info("Successfully completed nmap scan on Docker exposed ports.")

@pytest.mark.docker_security   
def test_nmap_open_ports_mqtt_docker(setup_docker_environment):
    logger.info("TC_007: Verify nmap open ports functionality with mqtt using Docker.")
    
    # Access the context from setup_docker_environment fixture
    context = setup_docker_environment
    
    # Deploy and verify Docker containers with MQTT ingestion (includes nmap scan)
    results = docker_utils.deploy_and_verify(context, deploy_type="mqtt", include_nmap=True)
    
    logger.info("Successfully completed nmap scan on Docker exposed ports.")
  
@pytest.mark.docker_security
def test_authentication_influx_grafana_docker(setup_docker_environment):
    logger.info("TC_008: Verify influxdb authentication and grafana authentication for Docker deployment.")
    
    # Access the context from setup_docker_environment fixture
    context = setup_docker_environment
    
    # Deploy and verify Docker containers with OPC-UA ingestion (without nmap scan)
    results = docker_utils.deploy_and_verify(context, deploy_type="opcua", include_nmap=False)
    
    # Test InfluxDB authentication using Docker-specific function
    influxdb_username, influxdb_password = security_utils.fetch_docker_credentials("influxdb")
    logger.info("Successfully retrieved InfluxDB credentials.")
    influxdb_login_result = security_utils.influxdb_login_docker()
    logger.info(f"influxdb_login_docker result: {influxdb_login_result}")
    assert_condition(influxdb_login_result == True, "Failed to login to InfluxDB with provided credentials.")
    
    # Test Grafana authentication using Docker-specific function
    grafana_username, grafana_password = security_utils.fetch_docker_credentials("grafana")
    logger.info("Successfully retrieved Grafana credentials.")
    grafana_login_result = asyncio.run(security_utils.login_to_grafana_docker(port=context["docker_grafana_port"]))
    logger.info(f"login_to_grafana_docker result: {grafana_login_result}")
    assert_condition(grafana_login_result == True, "Failed to login to Grafana with provided credentials.")
    
    logger.info("Successfully completed authentication tests for Docker deployment.")


@pytest.mark.docker_security
def test_verify_sensitive_data_in_mqtt_logs(setup_docker_environment):
    """
    TC_009: Test credentials verification in MQTT deployment
    
    Verify that:
    1. Environment variables can be read from .env file (set by fixture)
    2. MQTT deployment can be started with those credentials
    3. Containers are running properly
    4. Credentials are present in container logs
    """
    logger.info("TC_009: Testing MQTT deployment with credentials verification in logs")
    
    # Use the setup fixture to get the environment ready
    context = setup_docker_environment
    
    # Read the current values from .env file that were set by the fixture
    env_file_path = os.path.join(constants.EDGE_AI_SUITES_DIR, ".env")
    logger.info("Reading credentials from .env file that were set by the fixture")
    
    # Use the function we created to read environment variables from .env file
    env_vars = docker_utils.read_env_file(env_file_path)
    
    # Log the credential fields we'll be checking (without exposing the actual values)
    credential_fields = docker_utils.get_credential_fields()
    found_credentials = [field for field in credential_fields if field in env_vars]
    logger.info(f"Found credential fields in .env: {found_credentials}")
    
    # Verify the deployment with credentials set by the fixture
    results = docker_utils.verify_deployment_with_credentials(ingestion_type="mqtt")
    
    # Log detailed results (without exposing credential values)
    safe_results = results.copy()
    if "env_vars" in safe_results:
        credential_count = len([k for k in safe_results["env_vars"] if k in credential_fields])
        safe_results["env_vars"] = f"{credential_count} credential variables found"
    logger.info(f"Verification results: {safe_results}")
    
    # Check if verification was successful
    logger.info(f"Credential verification results: success={results['success']}, env_read={results.get('env_variables_read')}, deploy={results.get('deployment_success')}, containers_up={results.get('containers_up')}, creds_in_logs={results.get('credentials_in_logs')}")
    assert_condition(results["success"], f"Credential verification failed at step: {results.get('failed_step', 'unknown')}")
    
    logger.info("Successfully verified MQTT deployment with credentials in logs")
    
    # Individual assertions for better test reporting
    assert_condition(results["env_variables_read"], "Failed to read environment variables")
    assert_condition(results["deployment_success"], "Failed to deploy containers")
    assert_condition(results["containers_up"], "Containers are not running")
    assert_condition(results["credentials_in_logs"], "Credentials not found in container logs")
    
    # Cleanup handled by fixture

@pytest.mark.docker_security
def test_verify_sensitive_data_in_opcua_logs(setup_docker_environment):
    """
    TC_009: Test credentials verification in OPCUA deployment
    
    Verify that:
    1. Environment variables can be read from .env file (set by fixture)
    2. OPCUA deployment can be started with those credentials
    3. Containers are running properly
    4. Credentials are present in container logs
    """
    logger.info("TC_009: Testing OPCUA deployment with credentials verification in logs")
    
    # Use the setup fixture to get the environment ready
    context = setup_docker_environment
    
    # Read the current values from .env file that were set by the fixture
    env_file_path = os.path.join(constants.EDGE_AI_SUITES_DIR, ".env")
    logger.info("Reading credentials from .env file that were set by the fixture")
    
    # Use the function we created to read environment variables from .env file
    env_vars = docker_utils.read_env_file(env_file_path)
    
    # Log the credential fields we'll be checking (without exposing the actual values)
    credential_fields = docker_utils.get_credential_fields()
    found_credentials = [field for field in credential_fields if field in env_vars]
    logger.info(f"Found credential fields in .env: {found_credentials}")
    
    # Verify the deployment with credentials set by the fixture
    results = docker_utils.verify_deployment_with_credentials(ingestion_type="opcua")
    
    # Log detailed results (without exposing credential values)
    safe_results = results.copy()
    if "env_vars" in safe_results:
        credential_count = len([k for k in safe_results["env_vars"] if k in credential_fields])
        safe_results["env_vars"] = f"{credential_count} credential variables found"
    logger.info(f"Verification results: {safe_results}")
    
    # Check if verification was successful
    logger.info(f"Credential verification results: success={results['success']}, env_read={results.get('env_variables_read')}, deploy={results.get('deployment_success')}, containers_up={results.get('containers_up')}, creds_in_logs={results.get('credentials_in_logs')}")
    assert_condition(results["success"], f"Credential verification failed at step: {results.get('failed_step', 'unknown')}")
    
    logger.info("Successfully verified OPCUA deployment with credentials in logs")
    
    # Individual assertions for better test reporting
    assert_condition(results["env_variables_read"], "Failed to read environment variables")
    assert_condition(results["deployment_success"], "Failed to deploy containers")
    assert_condition(results["containers_up"], "Containers are not running")
    assert_condition(results["credentials_in_logs"], "Credentials not found in container logs")
    
    # Cleanup handled by fixture
