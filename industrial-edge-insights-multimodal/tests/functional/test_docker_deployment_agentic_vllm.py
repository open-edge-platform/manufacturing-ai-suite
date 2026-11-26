#
# Apache v2 license
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#

import os
import sys
import logging

import pytest

# Add parent directory to path for utils imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from utils import docker_utils
from utils import constants


# Import the fixture directly from conftest_docker.py
pytest_plugins = ["conftest_docker"]

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_MULTIMODAL_VLLM_AGENTIC_TESTS", "false").lower() != "true",
    reason=(
        "Requires Panther Lake hardware and deployment devices; set "
        "RUN_MULTIMODAL_VLLM_AGENTIC_TESTS=true on a compatible runner"
    ),
)

logger = logging.getLogger(__name__)


def test_multimodal_make_up_vllm(setup_multimodal_environment):
    """TC_020: Testing 'make up_vllm' brings up all containers running and healthy"""
    logger.info("TC_020: Testing multimodal 'make up_vllm' deployment")

    base_containers = constants.get_app_config(constants.MULTIMODAL_SAMPLE_APP)["multimodal_container_list"]
    containers = (
        base_containers
        + constants.MULTIMODAL_SEAWEEDFS_CONTAINERS
        + constants.MULTIMODAL_VLLM_EXTRA_CONTAINERS
    )

    docker_utils._verify_stack_running_and_healthy("up_vllm", containers)


def test_multimodal_make_up_agentic(setup_multimodal_environment):
    """TC_021: Testing 'make up_agentic' brings up all containers running and healthy"""
    logger.info("TC_021: Testing multimodal 'make up_agentic' deployment")

    base_containers = constants.get_app_config(constants.MULTIMODAL_SAMPLE_APP)["multimodal_container_list"]
    containers = (
        base_containers
        + constants.MULTIMODAL_SEAWEEDFS_CONTAINERS
        + constants.MULTIMODAL_VLLM_EXTRA_CONTAINERS
        + constants.MULTIMODAL_AGENTIC_EXTRA_CONTAINERS
    )

    docker_utils._verify_stack_running_and_healthy("up_agentic", containers)
