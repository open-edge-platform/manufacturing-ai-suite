# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import os
from pathlib import Path
import subprocess
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "weld-fleet-setup.sh"


class UserSystemdTests(unittest.TestCase):
    def run_check(self, *, available=False, socket=True, owner=True, retry=True,
                  missing_environment=False):
        source = SCRIPT.read_text()
        self.assertTrue("ensure_user_systemd() {\n" in source, "Session recovery helper missing")
        helper = source.split("ensure_user_systemd() {\n", 1)[1].split("\n}\n", 1)[0]
        harness = r"""
set -euo pipefail
calls=0
log() { printf '%s\n' "$*" >&2; }
die() { log "$*"; exit 1; }
id() { printf '12345\n'; }
test() {
  case "$1" in
    -S) [[ $SOCKET == 1 ]] ;;
    -O) [[ $OWNER == 1 ]] ;;
    *) builtin test "$@" ;;
  esac
}
systemctl() {
  calls=$((calls + 1))
  if [[ $AVAILABLE == 1 ]] ||
     [[ $calls -gt 1 && $RETRY == 1 &&
        ${XDG_RUNTIME_DIR:-} == /run/user/12345 &&
        ${DBUS_SESSION_BUS_ADDRESS:-} == unix:path=/run/user/12345/bus ]]; then
    printf 'SECRET_MANAGER_ENVIRONMENT\n'
    return 0
  fi
  printf 'Failed to connect to bus: No medium found\n' >&2
  return 1
}
"""
        env = {
            **os.environ,
            "AVAILABLE": str(int(available)),
            "SOCKET": str(int(socket)),
            "OWNER": str(int(owner)),
            "RETRY": str(int(retry)),
            "XDG_RUNTIME_DIR": "/stale/runtime",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/stale/bus",
        }
        if missing_environment:
            env.pop("XDG_RUNTIME_DIR")
            env.pop("DBUS_SESSION_BUS_ADDRESS")
        result = subprocess.run(
            ["bash", "-c", harness + "\nensure_user_systemd() {\n" + helper
             + "\n}\nensure_user_systemd\n"
             + 'printf "READY:%s:%s\\n" "$XDG_RUNTIME_DIR" "$DBUS_SESSION_BUS_ADDRESS"\n'],
            env=env, capture_output=True, text=True, check=False,
        )
        self.assertNotIn("SECRET_MANAGER_ENVIRONMENT", result.stdout + result.stderr)
        return result

    def test_working_session_is_preserved(self):
        result = self.run_check(available=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("READY:/stale/runtime:unix:path=/stale/bus", result.stdout)

    def test_stale_session_is_recovered(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("READY:/run/user/12345:unix:path=/run/user/12345/bus", result.stdout)

    def test_missing_session_environment_is_recovered(self):
        result = self.run_check(missing_environment=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("READY:/run/user/12345:unix:path=/run/user/12345/bus", result.stdout)

    def test_prerequisite_calls_helper(self):
        source = SCRIPT.read_text().split(
            'log "START: Central host prerequisites and SSH keys"', 1
        )[1]
        self.assertIn('\nensure_user_systemd\ninstall -d', source)

    def test_missing_socket_fails_with_guidance(self):
        result = self.run_check(socket=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("normal login", result.stderr)

    def test_socket_owned_by_another_user_is_rejected(self):
        result = self.run_check(owner=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("READY:", result.stdout)

    def test_retry_failure_shows_underlying_error(self):
        result = self.run_check(retry=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to connect to bus: No medium found", result.stderr)
        self.assertIn("loginctl enable-linger", result.stderr)


if __name__ == "__main__":
    unittest.main()
