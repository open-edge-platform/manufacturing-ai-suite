# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKER = r"""
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["TEST_EVENTS"])
stage = os.environ["FLEET_STAGE"]
name = os.environ["SKILL_NAME"]
state = Path(os.environ["FLEET_STATE_DIR"])
event = root / f"{stage}-{name}"
if stage == "prepare":
    with (root / "central.lock").open("x"):
        assert not list(root.glob("deploy-*"))
        (state / "prepared").touch()
        event.touch()
    (root / "central.lock").unlink()
elif stage == "deploy":
    assert (state / "prepared").exists()
    assert len(list(root.glob("prepare-*"))) == 2
    event.touch()
    deadline = time.monotonic() + 3
    while len(list(root.glob("deploy-*"))) != 2:
        if time.monotonic() > deadline:
            sys.exit("Other recipe did not deploy concurrently")
        time.sleep(0.01)
    (root / f"finished-{name}").touch()
    if os.environ.get("TEST_FAIL") == name:
        (state / "failed").touch()
        sys.exit(9)
elif stage == "connect":
    with (root / "central.lock").open("x"):
        assert len(list(root.glob("finished-*"))) == 2
        event.touch()
    (root / "central.lock").unlink()
    if (state / "failed").exists():
        sys.exit(9)
"""


class ParallelDeploymentTests(unittest.TestCase):
    def run_inventory(self, *options, fail=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            doc = yaml.safe_load((ROOT / "hosts.example.yaml").read_text())
            doc["nodes"] = [doc["nodes"][0]]
            doc["defaults"].pop("identity_file", None)
            doc["recipes"]["weld"]["source_delivery"] = "node_clone"
            other = copy.deepcopy(doc["recipes"]["weld"])
            other["remote_root"] = "wind-turbine"
            other["skill"]["name"] = "time-series-deploy"
            other["mcp"]["port"] = 3001
            doc["recipes"]["wind_turbine"] = other
            doc["nodes"][0]["deployments"].append(
                {"recipe": "wind_turbine", "name": "turbine_node1", "local_port": 13002}
            )
            hosts = root / "hosts.yaml"
            hosts.write_text(yaml.safe_dump(doc))
            worker = root / "worker.py"
            worker.write_text(WORKER)
            script = root / "worker.sh"
            script.write_text('#!/usr/bin/env bash\nset -euo pipefail\nexec python3 "$TEST_WORKER"\n')
            events = root / "events"
            events.mkdir()
            result = subprocess.run(
                ["python3", str(ROOT / "fleet_inventory.py"), "--hosts", str(hosts),
                 "--script", str(script), *options],
                env={**os.environ, "TEST_EVENTS": str(events), "TEST_WORKER": str(worker),
                     "TEST_FAIL": fail},
                capture_output=True, text=True, timeout=15, check=False,
            )
            return result, {path.name for path in events.iterdir()}

    def test_recipes_deploy_concurrently_and_central_stages_serialize(self):
        result, events = self.run_inventory()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len([name for name in events if name.startswith("connect-")]), 2)

    def test_failure_does_not_skip_other_recipe_or_connection(self):
        result, events = self.run_inventory(fail="multimodal-deploy")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("connect-time-series-deploy", events)
        self.assertIn("connect-multimodal-deploy", events)
        self.assertIn("wind_turbine\t0", result.stdout)
        self.assertIn("weld\t9", result.stdout)

    def test_interactive_multi_deployment_is_rejected_before_side_effects(self):
        result, events = self.run_inventory("--interactive")
        self.assertEqual(result.returncode, 2)
        self.assertIn("omit --interactive", result.stderr)
        self.assertFalse(events)

    def test_list_does_not_start_workers(self):
        result, events = self.run_inventory("--list")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(events)


if __name__ == "__main__":
    unittest.main()
