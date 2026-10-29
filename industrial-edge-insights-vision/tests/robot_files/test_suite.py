import unittest
import subprocess
import os
import shutil
import sys

env = os.environ.copy()


class test_suite(unittest.TestCase):

    ##################################################################################################################################################
    #                                   Test case with industrial_edge_insights_vision apps use cases
    ##################################################################################################################################################

    def _run_nose(self, test_target):
        python_executable = shutil.which("python3.10") or sys.executable
        return subprocess.call(
            [python_executable, "-m", "nose", "--nocapture", "-v", test_target],
            env=env,
        )

    def TC_001_PDD(self):
        env["TEST_CASE"] = "PDD001"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_002_PDD(self):
        env["TEST_CASE"] = "PDD002"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_003_PDD(self):
        env["TEST_CASE"] = "PDD003"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_004_PDD(self):
        env["TEST_CASE"] = "PDD004"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_005_PDD(self):
        env["TEST_CASE"] = "PDD005"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_001_PCB(self):
        env["TEST_CASE"] = "PCB001"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_002_PCB(self):
        env["TEST_CASE"] = "PCB002"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_003_PCB(self):
        env["TEST_CASE"] = "PCB003"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret

    def TC_004_PCB(self):
        env["TEST_CASE"] = "PCB004"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret
    
    def TC_005_PCB(self):
        env["TEST_CASE"] = "PCB005"
        ret = self._run_nose("../functional_tests/apps.py:TestCaseManager.test_apps")
        return ret
    
    def TC_001_PDDHELM(self):
        env["TEST_CASE"] = "PDDHELM001"
        ret = self._run_nose("../functional_tests/apps_helm.py:TestCaseManager.test_apps")
        return ret

    def TC_001_PCBHELM(self):
        env["TEST_CASE"] = "PCBHELM001"
        ret = self._run_nose("../functional_tests/apps_helm.py:TestCaseManager.test_apps")
        return ret



if __name__ == '__main__':
    unittest.main()