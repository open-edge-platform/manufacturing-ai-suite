# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
"""Validate deployment recipes and dispatch isolated node/app setup runs."""

import argparse
import hashlib
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

import yaml


def mapping(value, allowed, label):
    if not isinstance(value, dict) or any(not isinstance(k, str) for k in value):
        raise ValueError(f"{label}: expected a mapping with string keys")
    unknown = set(value) - set(allowed)
    if unknown:
        raise ValueError(f"{label}: unsupported keys: {', '.join(sorted(unknown))}")
    return value


def text(value, label, pattern=None):
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise ValueError(f"{label}: expected a non-empty string")
    if pattern and not re.fullmatch(pattern, value):
        raise ValueError(f"{label}: invalid format")
    return value


def relative(value, label):
    text(value, label, r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*")
    if any(part in (".", "..") for part in value.split("/")):
        raise ValueError(f"{label}: path traversal is not allowed")
    return value


def port(value, label, minimum=1):
    if type(value) is not int or not minimum <= value <= 65535:
        raise ValueError(f"{label}: expected integer {minimum}..65535")
    return value


def strings(value, label, pattern):
    if not isinstance(value, list):
        raise TypeError(f"{label}: expected a list")
    return [text(item, label, pattern) for item in value]


NAME = r"[a-z][a-z0-9_]{0,31}"
ENV_KEY = r"[A-Z_][A-Z0-9_]*"
SSH_KEYS = {"user", "port", "identity_file", "skip_platform_check"}


def recipe_config(name, raw):
    text(name, "recipe name", NAME)
    r = mapping(
        raw,
        {
            "repository",
            "ref",
            "remote_root",
            "app_dir",
            "skill",
            "prompt",
            "approval_policy",
            "environment",
            "mcp",
            "source_delivery",
        },
        name,
    )
    env = {}
    delivery = r.get("source_delivery", "node_clone")
    if delivery not in ("node_clone", "central_copy"):
        raise ValueError("source_delivery must be node_clone or central_copy")
    env["SOURCE_DELIVERY"] = delivery
    for key, field in (("REPO_URL", "repository"), ("REPO_BRANCH", "ref")):
        pattern = (
            r"https://[A-Za-z0-9./_-]+"
            if field == "repository"
            else r"[A-Za-z0-9_][A-Za-z0-9._/-]*"
        )
        env[key] = text(r.get(field), f"{name}.{field}", pattern)
    env["REMOTE_ROOT"] = relative(r.get("remote_root"), f"{name}.remote_root")
    app_dir = r.get("app_dir")
    env["APP_SUBDIR"] = "." if app_dir == "." else relative(app_dir, f"{name}.app_dir")
    skill = mapping(
        r.get("skill"), {"name", "path", "repository", "ref"}, f"{name}.skill"
    )
    env["SKILL_NAME"] = text(
        skill.get("name"), f"{name}.skill.name", r"[a-z][a-z0-9_-]{0,63}"
    )
    env["SKILL_PATH"] = relative(skill.get("path"), f"{name}.skill.path")
    env["SKILL_REPO_URL"] = text(
        skill.get("repository", r["repository"]),
        "skill.repository",
        r"https://[A-Za-z0-9./_-]+",
    )
    env["SKILL_REPO_REF"] = text(
        skill.get("ref", r["ref"]), "skill.ref", r"[A-Za-z0-9_][A-Za-z0-9._/-]*"
    )
    env["DEPLOY_PROMPT"] = text(r.get("prompt"), f"{name}.prompt")
    env["SMART_POLICY"] = text(
        r.get("approval_policy", "ESCALATE every terminal command."),
        f"{name}.approval_policy",
    )
    settings = mapping(
        r.get("environment", {}),
        {"generate_users", "generate_passwords", "set"},
        f"{name}.environment",
    )
    for field, key in (
        ("generate_users", "USER_KEYS_JSON"),
        ("generate_passwords", "PASS_KEYS_JSON"),
    ):
        env[key] = json.dumps(strings(settings.get(field, []), field, ENV_KEY))
    updates = mapping(
        settings.get("set", {}),
        settings.get("set", {}).keys()
        if isinstance(settings.get("set", {}), dict)
        else (),
        "environment.set",
    )
    for key, value in updates.items():
        text(key, "environment variable name", ENV_KEY)
        # These are non-secret, single-token .env values, not shell expressions.
        text(value, f"environment.set.{key}", r"[A-Za-z0-9_./:@,+-]+")
        if re.search(r"PASSWORD|SECRET|TOKEN|PRIVATE_KEY", key):
            raise ValueError(
                "environment.set: secret values belong on the node, not in YAML"
            )
    if "HOST_IP" in updates and updates["HOST_IP"] not in ("127.0.0.1", "localhost"):
        raise ValueError("environment.set.HOST_IP must keep the app on loopback")
    generated = json.loads(env["USER_KEYS_JSON"]) + json.loads(env["PASS_KEYS_JSON"])
    if len(generated) != len(set(generated)) or set(generated) & updates.keys():
        raise ValueError(
            "environment: generated and fixed variable names must be unique"
        )
    env["ENV_UPDATES_JSON"] = json.dumps(updates)
    mcp = mapping(
        r.get("mcp"),
        {"port", "path", "scheme", "certificate", "auth", "tools"},
        f"{name}.mcp",
    )
    env["REMOTE_PORT"] = str(port(mcp.get("port"), "mcp.port"))
    env["MCP_PATH"] = text(mcp.get("path", "/mcp"), "mcp.path", r"/[A-Za-z0-9_./-]*")
    scheme = mcp.get("scheme", "https")
    if scheme not in ("http", "https"):
        raise ValueError("mcp.scheme must be http or https (inside SSH tunnel)")
    env["MCP_SCHEME"] = scheme
    cert = mapping(mcp.get("certificate", {}), {"container", "path"}, "mcp.certificate")
    env["MCP_CERT_CONTAINER"] = (
        text(cert["container"], "certificate.container", r"[A-Za-z0-9][A-Za-z0-9_.-]*")
        if "container" in cert
        else ""
    )
    env["MCP_CERT_PATH"] = ""
    if scheme == "https":
        env["MCP_CERT_PATH"] = text(
            cert.get("path"), "certificate.path", r"/[A-Za-z0-9_./-]+"
        )
        if ".." in PurePosixPath(env["MCP_CERT_PATH"]).parts:
            raise ValueError("certificate.path: path traversal is not allowed")
    auth = mapping(
        mcp.get("auth", {"type": "none"}),
        {"type", "username_key", "password_key", "token_key"},
        "mcp.auth",
    )
    kind = auth.get("type", "none")
    if kind not in ("none", "basic", "bearer"):
        raise ValueError("mcp.auth.type must be none, basic or bearer")
    expected_auth_keys = {
        "none": {"type"},
        "basic": {"type", "username_key", "password_key"},
        "bearer": {"type", "token_key"},
    }[kind]
    if set(auth) - expected_auth_keys:
        raise ValueError(f"mcp.auth: unexpected keys for {kind} authentication")
    env["MCP_AUTH_TYPE"] = kind
    for field, key in (
        ("username_key", "MCP_USER_KEY"),
        ("password_key", "MCP_PASS_KEY"),
        ("token_key", "MCP_TOKEN_KEY"),
    ):
        needed = (kind == "basic" and field != "token_key") or (
            kind == "bearer" and field == "token_key"
        )
        env[key] = text(auth.get(field), field, ENV_KEY) if needed else ""
    env["MCP_TOOLS_JSON"] = json.dumps(
        strings(mcp.get("tools", []), "mcp.tools", r"[A-Za-z0-9_.-]+")
    )
    env["FLEET_RECIPE_MODE"] = "1"
    return env


def build_plan(doc, selected_nodes=(), selected_recipes=(), user="intel", skip=False):
    mapping(doc, {"defaults", "recipes", "nodes"}, "inventory")
    defaults = mapping(doc.get("defaults", {}), SSH_KEYS, "defaults")
    recipes = mapping(
        doc.get("recipes"),
        doc.get("recipes", {}).keys() if isinstance(doc.get("recipes"), dict) else (),
        "recipes",
    )
    configs = {name: recipe_config(name, recipe) for name, recipe in recipes.items()}
    nodes = doc.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError("nodes must be a non-empty list")
    plan, names, endpoints, remote_ports, roots, local_ports = (
        [],
        set(),
        set(),
        set(),
        set(),
        set(),
    )
    profiles = set()
    for raw in nodes:
        node = {
            "user": user,
            "port": 22,
            "identity_file": "",
            "skip_platform_check": skip,
            **defaults,
            **mapping(raw, SSH_KEYS | {"name", "host", "deployments"}, "node"),
        }
        name = text(node.get("name"), "node.name", NAME)
        if name in names:
            raise ValueError(f"duplicate node name: {name}")
        names.add(name)
        host = text(node.get("host"), "node.host", r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}")
        if re.fullmatch(r"[0-9.]+", host):
            ipaddress.IPv4Address(host)
        text(node["user"], "node.user", r"[a-z_][a-z0-9_-]{0,31}")
        port(node["port"], "node.port")
        if type(node["skip_platform_check"]) is not bool:
            raise ValueError("skip_platform_check must be boolean")
        identity = node["identity_file"]
        if identity:
            identity = os.path.expanduser(text(identity, "identity_file"))
            text(identity, "identity_file", r"/[A-Za-z0-9_./-]+")
            if ".." in PurePosixPath(identity).parts:
                raise ValueError("identity_file: path traversal is not allowed")
        node["identity_file"] = identity
        deployments = node.get("deployments")
        if not isinstance(deployments, list) or not deployments:
            raise ValueError(f"{name}: deployments must be a non-empty list")
        for entry in deployments:
            d = mapping(entry, {"recipe", "name", "local_port"}, f"{name}.deployment")
            recipe = text(d.get("recipe"), "deployment.recipe", NAME)
            if recipe not in configs:
                raise ValueError(f"{name}: unknown recipe {recipe!r}")
            server = text(d.get("name", f"{name}_{recipe}"), "deployment.name", NAME)
            match = re.fullmatch(r"weld_node([0-9]+)", server)
            profile = f"weld-node-{match[1]}" if match else server.replace("_", "-")
            if profile in profiles:
                raise ValueError(f"duplicate Hermes profile: {profile}")
            profiles.add(profile)
            lp = port(d.get("local_port"), "deployment.local_port", 1024)
            config = dict(configs[recipe])
            original_root = config["REMOTE_ROOT"]
            config["REMOTE_ROOT"] = f"fleet-deployments/{server}/checkout"
            config["FLEET_CLEAN_CHECKOUT"] = "true"
            for field in ("DEPLOY_PROMPT", "SMART_POLICY"):
                config[field] = config[field].replace(
                    f"~/{original_root}", f"~/{config['REMOTE_ROOT']}"
                )
            config["DEPLOY_PROMPT"] = (
                f"Deployment app directory: ~/{config['REMOTE_ROOT']}/{config['APP_SUBDIR']}. "
                + config["DEPLOY_PROMPT"]
            )
            # Physical endpoint identity, not just inventory alias.
            physical = (host.lower(), node["port"])
            for seen, value, label in (
                (endpoints, server, "deployment name"),
                (local_ports, lp, "local port"),
                (remote_ports, (*physical, config["REMOTE_PORT"]), "node MCP port"),
                (
                    roots,
                    (*physical, node["user"], config["REMOTE_ROOT"]),
                    "node checkout",
                ),
            ):
                if value in seen:
                    raise ValueError(f"duplicate {label}: {value}")
                seen.add(value)
            if selected_nodes and name not in selected_nodes:
                continue
            if selected_recipes and recipe not in selected_recipes:
                continue
            worker_node = {k: node[k] for k in SSH_KEYS | {"host"}}
            worker_node.update(name=server, local_port=lp)
            plan.append((name, recipe, worker_node, config))
    if set(selected_nodes) - names:
        raise ValueError("unknown --node selector")
    if set(selected_recipes) - configs.keys():
        raise ValueError("unknown --recipe selector")
    if not plan:
        raise ValueError("no deployments match the selection")
    return plan


def prepare_source(settings, directory, sources):
    """Fetch once per repository/ref and create a self-contained, verified Git bundle."""
    if settings["SOURCE_DELIVERY"] != "central_copy":
        return {}
    key = (settings["REPO_URL"], settings["REPO_BRANCH"])
    if key in sources:
        return sources[key]
    root = Path(directory) / f"source-{len(sources)}"
    repository = root / "repository.git"
    root.mkdir()
    print(f"Fetching central app source ({key[1]})", flush=True)
    subprocess.run(
        [
            "git",
            "clone",
            "--bare",
            "--single-branch",
            "--branch",
            key[1],
            "--",
            key[0],
            str(repository),
        ],
        check=True,
    )

    def git(*args):
        return subprocess.run(
            ["git", f"--git-dir={repository}", *args],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    commit = git("rev-parse", "--verify", f"{key[1]}^{{commit}}")
    tree = git("ls-tree", "-r", commit)
    if any(line.startswith("160000 ") for line in tree.splitlines()):
        raise ValueError("central_copy does not support submodules; use node_clone")
    attributes = [
        line.split("\t", 1)[1]
        for line in tree.splitlines()
        if line.endswith(("\t.gitattributes", "/.gitattributes"))
    ]
    for path in attributes:
        if re.search(r"filter\s*=\s*lfs", git("show", f"{commit}:{path}")):
            raise ValueError("central_copy does not support Git LFS; use node_clone")
    git("update-ref", "refs/heads/fleet-source", commit)
    bundle = root / "source.bundle"
    git("bundle", "create", str(bundle), "refs/heads/fleet-source")
    with bundle.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    result = {
        "SOURCE_BUNDLE": str(bundle),
        "SOURCE_SHA256": digest,
        "SOURCE_COMMIT": commit,
    }
    sources[key] = result
    print(
        f"Central source ready: commit={commit}; reused for matching nodes", flush=True
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hosts", required=True)
    parser.add_argument("--script", required=True)
    parser.add_argument("--node", action="append", default=[])
    parser.add_argument("--recipe", action="append", default=[])
    parser.add_argument("--user", default="intel")
    parser.add_argument("--skip-platform-check", action="store_true")
    for option in ("list", "no-deploy", "interactive"):
        parser.add_argument(f"--{option}", action="store_true")
    args = parser.parse_args()
    try:
        with open(args.hosts) as stream:
            doc = yaml.safe_load(stream)
        plan = build_plan(
            doc, args.node, args.recipe, args.user, args.skip_platform_check
        )
    except yaml.YAMLError:
        print(
            "ERROR: invalid inventory YAML syntax (contents omitted)", file=sys.stderr
        )
        return 2
    except (OSError, ValueError, TypeError) as error:
        print(f"ERROR: invalid inventory: {error}", file=sys.stderr)
        return 2
    if args.list:
        print("NODE\tRECIPE\tMCP SERVER/PROFILE\tHOST\tLOCAL PORT\tSKILL")
        for name, recipe, node, env in plan:
            print(
                f"{name}\t{recipe}\t{node['name']}\t{node['host']}\t{node['local_port']}\t{env['SKILL_NAME']}"
            )
        return 0
    if args.interactive and len(plan) > 1 and not args.no_deploy:
        print(
            "ERROR: parallel deployments cannot share an interactive terminal; "
            "omit --interactive or select a single deployment with --node and --recipe",
            file=sys.stderr,
        )
        return 2
    # Serialize shared Hermes state changes, not the remote deployment work.
    groups = {}
    for name, recipe, node, settings in plan:
        groups[(recipe, node["name"])] = ([name], [node], settings)
    results = []
    sources = {}
    with tempfile.TemporaryDirectory(prefix="fleet-inventory-") as directory:
        prepared = []
        for index, ((recipe, _), (names, nodes, settings)) in enumerate(groups.items()):
            name = ",".join(names)
            inventory = Path(directory) / f"{index}.yaml"
            inventory.write_text(yaml.safe_dump({"nodes": nodes}))
            inventory.chmod(0o600)
            env = {**os.environ, **settings}
            if args.no_deploy:
                env["FLEET_CLEAN_CHECKOUT"] = "false"
            try:
                env.update(prepare_source(settings, directory, sources))
            except (OSError, ValueError, subprocess.CalledProcessError) as error:
                print(
                    f"ERROR: central source preparation failed for {recipe}: {error}",
                    file=sys.stderr,
                )
                results.append((name, recipe, 1))
                continue
            env.pop("SKILL_SRC", None)
            state = Path(directory) / f"state-{index}"
            state.mkdir(mode=0o700)
            env["FLEET_STATE_DIR"] = str(state)
            command = ["bash", args.script, "--hosts", str(inventory)]
            if args.no_deploy:
                command.append("--no-deploy")
            if args.interactive:
                command.append("--interactive")
            print(
                f"Preparing recipe {recipe} on {name} "
                f"(servers {', '.join(node['name'] for node in nodes)})",
                flush=True,
            )
            result = subprocess.run(
                command, env={**env, "FLEET_STAGE": "prepare"}, check=False
            )
            if result.returncode:
                results.append((name, recipe, result.returncode))
                continue
            prepared.append((name, recipe, command, env))
        running = []
        try:
            for name, recipe, command, env in prepared:
                print(f"Launching deployment recipe {recipe} on {name} in parallel", flush=True)
                process = subprocess.Popen(command, env={**env, "FLEET_STAGE": "deploy"})
                running.append((name, recipe, command, env, process))
            deployed = [
                (name, recipe, command, env, process.wait())
                for name, recipe, command, env, process in running
            ]
        finally:
            for _, _, _, _, process in running:
                if process.poll() is None:
                    process.terminate()
                    process.wait()
        for name, recipe, command, env, deploy_result in deployed:
            result = subprocess.run(
                command, env={**env, "FLEET_STAGE": "connect"}, check=False
            )
            results.append((name, recipe, deploy_result or result.returncode))
    print("\nNODES\tRECIPE\tEXIT")
    for name, recipe, result in results:
        print(f"{name}\t{recipe}\t{result}")
    return int(any(result for _, _, result in results))


if __name__ == "__main__":
    sys.exit(main())
