#!/usr/bin/env python3
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
"""One-shot verification of a scaffolded stack; prints compact evidence for the final summary.

Reads the names recorded by scaffold_stack.py (<app or stack dir>/.scaffold.json) and checks:
  - containers of the stack are running/healthy (multimodal family);
  - one MQTT message on each core topic (via `docker exec ia-mqtt-broker mosquitto_sub`);
  - InfluxDB row counts for the core measurements (credentials read from .env, never printed);
  - HTTPS endpoints through nginx, TLS-verified against the stack's own cert (never -k);
  - OpenMES publisher deliveries and, for the dummy receiver, its alert count and URL.

Usage:  python verify_stack.py <stack_dir | ts_repo/apps/<app>> [--wait 30]
Exit code: 0 when every check passed, 1 otherwise.
"""

import argparse
import json
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

RESULTS = []


def check(name, ok, evidence):
    RESULTS.append((name, ok))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {evidence}")


def run(cmd, timeout=60):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def env_value(env_file, key):
    for line in Path(env_file).read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip()
    return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", help="stack dir (multimodal family) or ts_repo/apps/<app>")
    ap.add_argument("--wait", type=int, default=30, help="seconds to wait for each MQTT topic")
    args = ap.parse_args()
    target = Path(args.target).resolve()
    meta_file = target / ".scaffold.json"
    if not meta_file.exists():
        sys.exit(f"{meta_file} not found (was this created by scaffold_stack.py?)")
    meta = json.loads(meta_file.read_text())
    mode, stack_dir = meta["mode"], Path(meta["stack_dir"])
    env_file = stack_dir / ".env"
    host = env_value(env_file, "HOST_IP") or meta.get("host_ip", "127.0.0.1")
    port = env_value(env_file, "GRAFANA_PORT") or "3000"
    if not shutil.which("docker"):
        sys.exit("docker not found")

    # containers
    if meta.get("compose_project"):
        rc, out = run(["docker", "ps", "-a", "--filter", f"label=com.docker.compose.project={meta['compose_project']}",
                       "--format", "{{.Names}}\t{{.Status}}"])
        rows = [ln.split("\t") for ln in out.strip().splitlines() if "\t" in ln]
        bad = [f"{n} ({s})" for n, s in rows
               if not s.startswith("Up") or "unhealthy" in s or "starting" in s
               if not (s.startswith("Exited (0)") and "init" in n)]
        check("containers", rc == 0 and rows and not bad,
              f"{len(rows)} containers; not ready: {', '.join(bad) or 'none'}")

    # MQTT
    for label, topic in meta.get("topics", {}).items():
        if label in ("sensor_alert",) and mode != "ts":
            continue
        rc, out = run(["docker", "exec", "ia-mqtt-broker", "mosquitto_sub", "-h", "localhost", "-t", topic,
                       "-C", "1", "-W", str(args.wait)], timeout=args.wait + 10)
        msg = out.strip().splitlines()[0][:180] if out.strip() else ""
        check(f"mqtt {topic}", rc == 0 and bool(msg), msg or "no message (timeout)")

    # InfluxDB
    user, pw = env_value(env_file, "INFLUXDB_USERNAME"), env_value(env_file, "INFLUXDB_PASSWORD")
    for label, meas in meta.get("measurements", {}).items():
        rc, out = run(["docker", "exec", "ia-influxdb", "influx", "-username", user, "-password", pw,
                       "-database", "datain", "-format", "json", "-execute",
                       f'SELECT count(*) FROM "{meas}"'])
        count = 0
        try:
            vals = json.loads(out)["results"][0]["series"][0]["values"][0][1:]
            count = max(int(v) for v in vals if v is not None)
        except (ValueError, KeyError, IndexError, TypeError):
            pass
        check(f"influx {meas}", count > 0, f"{count} rows")

    # HTTPS through nginx, verified against the stack's own certificate
    with tempfile.TemporaryDirectory() as td:
        cert = Path(td) / "nginx-cert.pem"
        rc, _ = run(["docker", "cp", "nginx_proxy:/opt/nginx/certs/cert.pem", str(cert)])
        if rc != 0:
            check("https", False, "could not copy nginx_proxy cert")
        else:
            for path in meta.get("https_paths", []):
                rc, out = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--noproxy", "*",
                               "--cacert", str(cert), "--resolve", f"localhost:{port}:{host}",
                               f"https://localhost:{port}{path}"], timeout=30)
                code = out.strip()[-3:]
                check(f"https {path}", code[:1] in ("2", "3"), f"HTTP {code}")

    # OpenMES
    om = meta.get("openmes")
    if om:
        log = Path(om["dir"]) / "publisher.log"
        delivered = errors = 0
        if log.exists():
            text = log.read_text(errors="ignore")
            delivered, errors = text.count("Delivered event="), len(re.findall(r" ERROR ", text))
        check("openmes publisher", delivered > 0 and errors == 0,
              f"{delivered} delivered, {errors} errors (log: {log})")
        if om.get("dummy"):
            try:
                ctx = ssl.create_default_context()
                with urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                                 urllib.request.HTTPSHandler(context=ctx)).open(
                        om["ui_url"].rstrip("/") + "/ui/api/issues?since_id=999999999", timeout=10) as r:
                    s = json.load(r)
                check("dummy OpenMES receiver", s["total"] > 0,
                      f"{s['total']} alerts, rejected {s.get('rejected') or {}} - alerts page: {om['ui_url']}")
            except OSError as exc:
                check("dummy OpenMES receiver", False, f"{om['ui_url']} unreachable ({exc}); "
                      f"run {om['dir']}/start_dummy_openmes.sh")

    failed = [n for n, ok in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} checks passed" +
          (f"; failed: {', '.join(failed)}" if failed else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
