#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# Prepares nodes, installs deployment skills, deploys apps with their MCP servers,
# and registers each node's MCP server with the Hermes on this host.
set -euo pipefail

SSH_USER=intel
SKIP_PLATFORM_CHECK=false
DEPLOY=true
INTERACTIVE=false
HOSTS_FILE=
LIST_ONLY=false
SELECTORS=()

REPO_URL=${REPO_URL:-https://github.com/vkb1/manufacturing-ai-suite.git}
REPO_BRANCH=${REPO_BRANCH:-feature/hermes-skill-mcp-integration}
REMOTE_ROOT=${REMOTE_ROOT:-manufacturing-ai-suite}
APP_SUBDIR=${APP_SUBDIR:-industrial-edge-insights-multimodal}
APP_REL="$REMOTE_ROOT/$APP_SUBDIR"
REMOTE_PORT=${REMOTE_PORT:-3000}
BASE_PORT=13000
USER_KEYS=(INFLUXDB_USERNAME VISUALIZER_GRAFANA_USER MTX_WEBRTCICESERVERS2_0_USERNAME S3_STORAGE_USERNAME SEAWEEDFS_WEB_AUTH_USER MCP_USERNAME)
PASS_KEYS=(INFLUXDB_PASSWORD VISUALIZER_GRAFANA_PASSWORD MTX_WEBRTCICESERVERS2_0_PASSWORD S3_STORAGE_PASSWORD SEAWEEDFS_WEB_AUTH_PASSWORD MCP_PASSWORD)
MCP_TOOLS='["describe","list_insights_data","explain","run_agent","get_run_results","start_pipeline","stop_pipeline"]'
SKILL_NAME=${SKILL_NAME:-multimodal-deploy}
SKILL_PATH=${SKILL_PATH:-$APP_SUBDIR/.github/skills/$SKILL_NAME}
SKILL_REPO_URL=${SKILL_REPO_URL:-$REPO_URL}
SKILL_REPO_REF=${SKILL_REPO_REF:-$REPO_BRANCH}
MCP_SCHEME=${MCP_SCHEME:-https}
MCP_PATH=${MCP_PATH:-/mcp}
MCP_CERT_CONTAINER=${MCP_CERT_CONTAINER-nginx_proxy}
MCP_CERT_PATH=${MCP_CERT_PATH:-/opt/nginx/certs/cert.pem}
MCP_AUTH_TYPE=${MCP_AUTH_TYPE:-basic}
MCP_USER_KEY=${MCP_USER_KEY:-MCP_USERNAME}
MCP_PASS_KEY=${MCP_PASS_KEY:-MCP_PASSWORD}
MCP_TOKEN_KEY=${MCP_TOKEN_KEY:-MCP_TOKEN}
if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
  mapfile -t USER_KEYS < <(python3 -c 'import json,os; print("\n".join(json.loads(os.environ["USER_KEYS_JSON"])))')
  mapfile -t PASS_KEYS < <(python3 -c 'import json,os; print("\n".join(json.loads(os.environ["PASS_KEYS_JSON"])))')
  # Empty lists must not create a single empty variable name.
  [[ -n ${USER_KEYS[0]:-} ]] || USER_KEYS=()
  [[ -n ${PASS_KEYS[0]:-} ]] || PASS_KEYS=()
  MCP_TOOLS=${MCP_TOOLS_JSON:-'[]'}
fi
DEPLOY_PROMPT=${DEPLOY_PROMPT:-"In ~/$APP_REL, Meet prerequisites (ignore accepting licenses for downloading models from HF), build time series analytics microservice, build and deploy (pull latest weekly tags of intel/ images) the agentic variant with the MCP server (make up_agentic MCP=true), then run the smoke check. Do not edit .env; if a required credential is missing, stop and name it. Do not start or stop pipelines."}
SMART_POLICY=${SMART_POLICY:-"APPROVE make build, make up_agentic, make down and make status (with or without MCP=true) and .github/skills/multimodal-deploy/scripts/smoke-check.sh when run from ~/$APP_REL. ESCALATE anything that edits .env, uses sudo, or touches paths outside that directory."}

RUN_STARTED=$SECONDS
log() { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] [+%ss] %s\n' -1 "$((SECONDS - RUN_STARTED))" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
stage_finished() {
  if (( $1 == 0 )); then
    log "DONE: $STAGE_LABEL (elapsed=$((SECONDS - STAGE_STARTED))s)"
  else
    log "ERROR: $STAGE_LABEL (exit=$1, elapsed=$((SECONDS - STAGE_STARTED))s)"
  fi
}
run_stage() (
  STAGE_LABEL=$1 STAGE_STARTED=$SECONDS
  shift
  trap 'stage_finished "$?"' EXIT
  log "START: $STAGE_LABEL"
  "$@"
)
usage() {
  cat >&2 <<EOF
usage: $0 [--hosts FILE] [--list] [--user NAME] [--interactive] [--no-deploy] [--skip-platform-check]
       $0 [--list] [--user NAME] [--interactive] [--no-deploy] [--skip-platform-check] <node-ip> [<node-ip> ...]
Without node IPs, nodes are read from FILE (default: hosts.yaml next to this script).
--list prints the resolved nodes and exits without changing anything.
--node NAME and --recipe NAME select deployments from a recipe inventory (repeatable).
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --hosts) [[ $# -ge 2 ]] || usage; HOSTS_FILE=$2; shift 2 ;;
    --list) LIST_ONLY=true; shift ;;
    --node|--recipe) [[ $# -ge 2 ]] || usage; SELECTORS+=("$1" "$2"); shift 2 ;;
    --user) [[ $# -ge 2 ]] || usage; SSH_USER=$2; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --no-deploy) DEPLOY=false; shift ;;
    --skip-platform-check) SKIP_PLATFORM_CHECK=true; shift ;;
    -h|--help|-*) usage ;;
    *) break ;;
  esac
done
if [[ $# == 0 && ${FLEET_RECIPE_MODE:-} != 1 ]]; then
  HOSTS_FILE=${HOSTS_FILE:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hosts.yaml"}
  command -v python3 >/dev/null || die "python3 is required for YAML inventories"
  python3 -c 'import yaml' 2>/dev/null || die "PyYAML is required (install python3-yaml)"
  inventory_kind=$(python3 - "$HOSTS_FILE" <<'PY'
import sys, yaml
try:
    with open(sys.argv[1]) as stream:
        doc = yaml.safe_load(stream)
    print("recipes" if isinstance(doc, dict) and "recipes" in doc else "legacy")
except (OSError, yaml.YAMLError):
    sys.exit("ERROR: cannot read inventory; check the file path and YAML syntax")
PY
  ) || exit 2
  if [[ $inventory_kind == recipes ]]; then
    inventory_args=(--hosts "$HOSTS_FILE" --script "${BASH_SOURCE[0]}" --user "$SSH_USER" "${SELECTORS[@]}")
    $LIST_ONLY && inventory_args+=(--list)
    $INTERACTIVE && inventory_args+=(--interactive)
    $DEPLOY || inventory_args+=(--no-deploy)
    $SKIP_PLATFORM_CHECK && inventory_args+=(--skip-platform-check)
    exec python3 "$(dirname "${BASH_SOURCE[0]}")/fleet_inventory.py" "${inventory_args[@]}"
  fi
fi
(( ${#SELECTORS[@]} == 0 )) || die "--node/--recipe require a recipe inventory"
[[ $# -ge 1 && -n $HOSTS_FILE ]] && die "give either --hosts or node IPs, not both"
[[ $SSH_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid --user: $SSH_USER"
[[ $REPO_URL =~ ^https://[A-Za-z0-9./_-]+$ ]] || die "invalid REPO_URL: $REPO_URL"
[[ $REPO_BRANCH =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid REPO_BRANCH: $REPO_BRANCH"

# Per-node settings by position (0-based). Node N (1-based) defaults to name weld_nodeN and local port BASE_PORT+N.
NAME=() HOST=() NUSER=() SSH_PORT=() KEY=() LPORT=() SKIP=()

# Prints one tab-separated line per node: name host user port identity_file local_port skip_platform_check.
read_hosts_file() {
  command -v python3 >/dev/null || die "python3 is needed to read $1"
  python3 -c 'import yaml' 2>/dev/null || die "PyYAML is needed to read $1 (sudo apt-get install python3-yaml)"
  python3 - "$1" "$SSH_USER" "$SKIP_PLATFORM_CHECK" <<'PY'
import sys, yaml

path, cli_user, cli_skip = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
NODE_KEYS = {"name", "host", "user", "port", "identity_file", "local_port", "skip_platform_check"}
DEFAULT_KEYS = {"user", "port", "identity_file", "skip_platform_check"}

def fail(msg):
    sys.exit(f"ERROR: {path}: {msg}")

try:
    with open(path) as f:
        doc = yaml.safe_load(f) or {}
except (OSError, yaml.YAMLError) as e:
    fail(f"cannot read: {e}")
if not isinstance(doc, dict) or set(doc) - {"defaults", "nodes"}:
    fail("the top level may contain only 'defaults' and 'nodes'")
defaults = doc.get("defaults") or {}
nodes = doc.get("nodes") or []
if not isinstance(defaults, dict):
    fail("'defaults' must be a mapping")
if not isinstance(nodes, list) or not nodes:
    fail("'nodes' must be a non-empty list")
for d in [defaults, *nodes]:
    if isinstance(d, dict) and any("pass" in str(k).lower() for k in d):
        fail("passwords are not supported; use key-based SSH (identity_file)")
if set(defaults) - DEFAULT_KEYS:
    fail(f"'defaults' may contain only {sorted(DEFAULT_KEYS)}")

for i, node in enumerate(nodes, 1):
    if not isinstance(node, dict):
        fail(f"node {i} must be a mapping")
    if set(node) - NODE_KEYS:
        fail(f"node {i}: unknown keys {sorted(set(node) - NODE_KEYS)}")
    if "host" not in node:
        fail(f"node {i}: 'host' is required")
    v = {"name": f"weld_node{i}", "user": cli_user, "port": 22, "identity_file": "", "local_port": 0,
         "skip_platform_check": cli_skip, **defaults, **node}
    if v["name"] == "default":
        fail(f"node {i}: name 'default' is reserved for Hermes' central profile")
    if not isinstance(v["skip_platform_check"], bool):
        fail(f"node {i}: skip_platform_check must be true or false")
    for k in ("port", "local_port"):
        if not isinstance(v[k], int) or isinstance(v[k], bool):
            fail(f"node {i}: {k} must be a number")
    fields = [str(x) for x in (v["name"], v["host"], v["user"], v["port"], v["identity_file"] or "-",
                               v["local_port"], str(v["skip_platform_check"]).lower())]
    if any(not x or any(c.isspace() for c in x) for x in fields):
        fail(f"node {i}: values must be non-empty and contain no whitespace")
    print("\t".join(fields))
PY
}

valid_host() {
  local h=$1 o
  if [[ $h =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
    return 0
  fi
  [[ ${#h} -le 253 && $h =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$ ]]
}

if [[ $# -ge 1 ]]; then
  for ip in "$@"; do
    NAME+=("weld_node$((${#NAME[@]} + 1))") HOST+=("$ip") NUSER+=("$SSH_USER") SSH_PORT+=(22) KEY+=("")
    LPORT+=(0) SKIP+=("$SKIP_PLATFORM_CHECK")
  done
else
  HOSTS_FILE=${HOSTS_FILE:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hosts.yaml"}
  [[ -f $HOSTS_FILE ]] || { echo "ERROR: no node IPs given and $HOSTS_FILE not found" >&2; usage; }
  hosts_tsv=$(read_hosts_file "$HOSTS_FILE") || exit 1
  while IFS=$'\t' read -r n h u p k lp sk; do
    [[ $k == - ]] && k=""
    NAME+=("$n") HOST+=("$h") NUSER+=("$u") SSH_PORT+=("$p") KEY+=("$k") LPORT+=("$lp") SKIP+=("$sk")
  done <<<"$hosts_tsv"
fi

declare -A seen_name seen_port
for i in "${!NAME[@]}"; do
  n=${NAME[i]}
  [[ $n =~ ^[a-z][a-z0-9_]{0,31}$ ]] || die "invalid node name: $n (lowercase letters, digits, _)"
  [[ $n != default ]] || die "node name 'default' is reserved for Hermes' central profile"
  valid_host "${HOST[i]}" || die "[$n] not an IPv4 address or hostname: ${HOST[i]}"
  [[ ${NUSER[i]} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "[$n] invalid user: ${NUSER[i]}"
  if ! [[ ${SSH_PORT[i]} =~ ^[0-9]{1,5}$ ]] || (( SSH_PORT[i] < 1 || SSH_PORT[i] > 65535 )); then
    die "[$n] invalid port: ${SSH_PORT[i]}"
  fi
  [[ ${LPORT[i]} == 0 ]] && LPORT[i]=$((BASE_PORT + i + 1))
  if ! [[ ${LPORT[i]} =~ ^[0-9]{4,5}$ ]] || (( LPORT[i] < 1024 || LPORT[i] > 65535 )); then
    die "[$n] invalid local_port: ${LPORT[i]}"
  fi
  if [[ -n ${KEY[i]} ]]; then
    # shellcheck disable=SC2088  # matching a literal "~/" from the hosts file
    [[ ${KEY[i]} == "~/"* ]] && KEY[i]="$HOME/${KEY[i]:2}"
    [[ ${KEY[i]} =~ ^/[A-Za-z0-9._/-]+$ && ${KEY[i]} != *..* ]] \
      || die "[$n] identity_file must be an absolute or ~/ path without spaces: ${KEY[i]}"
  fi
  [[ ${SKIP[i]} == true || ${SKIP[i]} == false ]] || die "[$n] invalid skip_platform_check: ${SKIP[i]}"
  [[ -z ${seen_name[$n]:-} ]] || die "duplicate node name: $n"
  [[ -z ${seen_port[${LPORT[i]}]:-} ]] || die "[$n] local_port ${LPORT[i]} is already used by ${seen_port[${LPORT[i]}]}"
  seen_name[$n]=1 seen_port[${LPORT[i]}]=$n
done

# Hermes profile per node: weld_nodeN -> weld-node-N (as in the manual sections); other names: _ -> -.
profile_of() {
  if [[ $1 =~ ^weld_node([0-9]+)$ ]]; then printf 'weld-node-%s' "${BASH_REMATCH[1]}"; else printf '%s' "${1//_/-}"; fi
}

# ssh and scp with the node's port and key; the first argument is the node index.
node_opts() {
  local i=$1 port_flag=$2
  NODE_OPTS=("$port_flag" "${SSH_PORT[i]}")
  if [[ -n ${KEY[i]} ]]; then NODE_OPTS+=(-i "${KEY[i]}" -o IdentitiesOnly=yes); fi
}
# shellcheck disable=SC2029  # remote commands are fixed strings with validated arguments
nssh() { node_opts "$1" -p; shift; ssh "${NODE_OPTS[@]}" "$@"; }
nscp() { node_opts "$1" -P; shift; scp -q "${NODE_OPTS[@]}" "$@"; }

if $LIST_ONLY; then
  printf '%-11s %-15s %-10s %-5s %-12s %-6s %-14s %s\n' NODE HOST USER PORT PROFILE LOCAL SKIP_PLATFORM IDENTITY_FILE
  for i in "${!NAME[@]}"; do
    printf '%-11s %-15s %-10s %-5s %-12s %-6s %-14s %s\n' "${NAME[i]}" "${HOST[i]}" "${NUSER[i]}" "${SSH_PORT[i]}" \
      "$(profile_of "${NAME[i]}")" "${LPORT[i]}" "${SKIP[i]}" "${KEY[i]:-(ssh default)}"
  done
  exit 0
fi

finish() {
  local result=$?
  if [[ -n ${LOCAL_TMP:-} && -z ${FLEET_STATE_DIR:-} ]]; then rm -rf "$LOCAL_TMP"; fi
  if (( result == 0 )); then
    log "DONE: Fleet setup (nodes=${#NAME[@]}, total=$((SECONDS - RUN_STARTED))s)"
  else
    log "ERROR: Fleet setup (exit=$result, total=$((SECONDS - RUN_STARTED))s); see the last stage above"
  fi
}
trap finish EXIT
log "Inventory validated: ${#NAME[@]} node(s); deploy=$DEPLOY; interactive=$INTERACTIVE"
if $INTERACTIVE && $DEPLOY && (( ${#NAME[@]} > 1 )); then
  die "Parallel deployments cannot share an interactive terminal; omit --interactive or select a single node"
fi
FLEET_STAGE=${FLEET_STAGE:-all}
case "$FLEET_STAGE" in
  all|prepare|deploy|connect) ;;
  *) die "invalid fleet stage: $FLEET_STAGE" ;;
esac
if [[ $FLEET_STAGE != all ]]; then
  [[ ${FLEET_RECIPE_MODE:-} == 1 && -d ${FLEET_STATE_DIR:-} ]] \
    || die "staged execution requires a recipe inventory and state directory"
fi

rand_user() { printf 'weld%s' "$(openssl rand -base64 48 | tr -dc 'a-z' | cut -c1-8)"; }
rand_pass() { printf '%sa7' "$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-22)"; }

set_central_env() {
  local f="$HOME/.hermes/.env" tmp
  tmp=$(mktemp "$f.XXXXXX")
  { grep -v "^$1=" "$f" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
  mv "$tmp" "$f"
}

write_helpers() {
  cat > "$LOCAL_TMP/node-prepare.sh" <<'REMOTE'
set -euo pipefail
repo_url=$1 branch=$2 root=$HOME/$3 app_subdir=$4
log() { printf '[%(%Y-%m-%dT%H:%M:%S%z)T] [remote +%ss] %s\n' -1 "$SECONDS" "$*" >&2; }
trap 'result=$?; log "Node preparation finished (exit=$result, elapsed=${SECONDS}s)"' EXIT
log "Checking packages and Docker Compose"
need=()
for c in make curl git; do command -v "$c" >/dev/null || need+=("$c"); done
command -v docker >/dev/null || need+=(docker.io)
docker compose version >/dev/null 2>&1 || need+=(docker-compose-v2)
if (( ${#need[@]} )); then
  command -v apt-get >/dev/null || { echo "Install these on $(hostname) first: ${need[*]}" >&2; exit 1; }
  log "Installing missing packages: ${need[*]} (sudo may prompt)"
  sudo apt-get update -q
  sudo apt-get install -y -q "${need[@]}"
fi
log "Package checks complete; checking Docker group membership"
if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then
  log "Adding deployment user to Docker group (sudo may prompt)"
  sudo usermod -aG docker "$USER"
fi
if [[ $3 == fleet-deployments/* ]]; then
  [[ $3 =~ ^fleet-deployments/[a-z][a-z0-9_]{0,31}/checkout$ ]] \
    || { echo "Refusing operation outside a managed deployment checkout" >&2; exit 1; }
  parent=${root%/checkout}
  base=$HOME/fleet-deployments
  for directory in "$base" "$parent"; do
    [[ ! -L $directory ]] && [[ ! -e $directory || ( -d $directory && -O $directory ) ]] \
      || { echo "Unsafe managed deployment directory" >&2; exit 1; }
    install -d -m 0700 "$directory"
  done
  marker=$parent/.managed-checkout
  [[ ! -L $marker && ( ! -e $marker || ( -f $marker && -O $marker ) ) ]] \
    || { echo "Unsafe managed checkout marker" >&2; exit 1; }
  if [[ -e $root || -L $root ]]; then
    [[ -f $marker && ! -L $marker && -O $marker &&
       $(cat "$marker") == fleet-checkout-v1 && -d $root && ! -L $root && -O $root ]] \
      || { echo "Refusing to use an unrecognized deployment checkout" >&2; exit 1; }
    if [[ ${9:-false} == true ]]; then
      log "Removing managed checkout; local credentials, models, and edits will be discarded"
      rm -rf -- "$root"
    fi
  elif [[ ! -e $marker ]]; then
    printf '%s\n' fleet-checkout-v1 > "$marker"
    chmod 600 "$marker"
  elif [[ ! -f $marker || ! -O $marker || $(cat "$marker") != fleet-checkout-v1 ]]; then
    echo "Unsafe managed checkout marker" >&2
    exit 1
  fi
elif [[ ${9:-false} == true ]]; then
  echo "Refusing cleanup outside a managed deployment checkout" >&2
  exit 1
fi
if [[ ${5:-node_clone} == central_copy ]]; then
  bundle=$6 digest=$7 commit=$8
  log "Verifying transferred Git bundle"
  printf '%s  %s\n' "$digest" "$bundle" | sha256sum --check --status
  git bundle list-heads "$bundle" >/dev/null
  if [[ -d $root/.git ]]; then
    log "Updating checkout from central bundle (no upstream fetch)"
    git -C "$root" fetch -q "$bundle" refs/heads/fleet-source
    [[ $(git -C "$root" rev-parse FETCH_HEAD) == "$commit" ]]
    git -C "$root" checkout -q --no-overwrite-ignore -B "$branch" FETCH_HEAD
  else
    [[ ! -e $root ]] || { echo "Existing non-Git path blocks source delivery" >&2; exit 1; }
    log "Creating checkout from central bundle (no upstream clone)"
    git clone -q --sparse --branch fleet-source "$bundle" "$root"
    git -C "$root" checkout -q -B "$branch" "$commit"
    git -C "$root" remote set-url origin "$repo_url"
  fi
  git -C "$root" bundle verify "$bundle"
  [[ $(git -C "$root" rev-parse HEAD) == "$commit" ]]
  log "Central source installed at commit $commit"
elif [[ -d $root/.git ]]; then
  log "Fetching app branch and updating existing checkout"
  git -C "$root" fetch -q "$repo_url" "$branch"
  git -C "$root" checkout -q -B "$branch" FETCH_HEAD \
    || { echo "Local changes in $root block switching to $branch (usually .env); commit or stash them and rerun" >&2; exit 1; }
else
  log "Cloning app branch (this may take several minutes)"
  git clone -q --filter=blob:none --sparse --branch "$branch" "$repo_url" "$root"
fi
if [[ $app_subdir != . ]]; then
  [[ $(git -C "$root" cat-file -t "HEAD:$app_subdir" 2>/dev/null) == tree ]] \
    || { echo "Requested app directory $app_subdir is not present in the selected source revision" >&2; exit 1; }
fi
if [[ $(git -C "$root" config --bool core.sparseCheckout) == true ]]; then
  if [[ $app_subdir == . ]]; then
    git -C "$root" sparse-checkout disable
  else
    log "Including requested app in existing sparse checkout"
    git -C "$root" sparse-checkout add "$app_subdir"
  fi
fi
[[ -d $root/$app_subdir ]] \
  || { echo "Requested app directory $app_subdir is missing after checkout preparation" >&2; exit 1; }
log "App checkout ready"
REMOTE

  cat > "$LOCAL_TMP/env-merge.sh" <<'REMOTE'
set -euo pipefail
env_file=$1 updates=$2
trap 'rm -f "$updates"' EXIT
touch "$env_file"
while read -r mode key val; do
  cur=$(sed -n "s/^${key}=//p" "$env_file" | tail -n 1)
  [[ $mode == fill && -n $cur ]] && continue
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$env_file"
  fi
done < "$updates"
chmod 600 "$env_file"
REMOTE
}

write_tunnel_unit() {
  install -d "$HOME/.config/systemd/user" "$HOME/.config/weld-tunnels"
  cat > "$HOME/.config/systemd/user/weld-tunnel@.service" <<'UNIT'
[Unit]
Description=SSH tunnel to multimodal nginx (%i)
After=network-online.target

[Service]
EnvironmentFile=%h/.config/weld-tunnels/%i.env
ExecStart=/usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 $SSH_OPTS -L ${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} ${NODE}
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  loginctl enable-linger "$USER" || log "WARN: could not enable linger; tunnels stop when you log out"
}

setup_profile() {
  local i=$1 ip=${HOST[$1]} p profiles dst
  p=$(profile_of "${NAME[i]}")
  log "[$p] Hermes profile for $ip"
  profiles=$(hermes profile list 2>/dev/null || true)
  if ! awk -v p="$p" '{ for (i = 1; i <= NF; i++) if ($i == p) found = 1 } END { exit !found }' <<<"$profiles"; then
    log "[${NAME[i]}] Creating Hermes profile"
    hermes profile create "$p" --clone --description "Runs $SKILL_NAME on $ip over SSH"
    hermes -p "$p" config unset mcp_servers >/dev/null 2>&1 || true
  fi
  log "[${NAME[i]}] Configuring SSH backend, timeout, approval policy, and deploy skill"
  hermes -p "$p" config set terminal.backend ssh
  hermes -p "$p" config set TERMINAL_SSH_HOST "$ip"
  hermes -p "$p" config set TERMINAL_SSH_USER "${NUSER[i]}"
  hermes -p "$p" config set TERMINAL_SSH_PORT "${SSH_PORT[i]}"
  if [[ -n ${KEY[i]} ]]; then
    hermes -p "$p" config set TERMINAL_SSH_KEY "${KEY[i]}"
  else
    hermes -p "$p" config unset TERMINAL_SSH_KEY >/dev/null 2>&1 || true
  fi
  hermes -p "$p" config set terminal.timeout 3600
  hermes -p "$p" config set approvals.smart_policy "$SMART_POLICY"
  dst="$HOME/.hermes/profiles/$p/skills/devops"
  install -d "$dst"
  [[ $SKILL_NAME =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || die "invalid skill name"
  rm -rf "${dst:?}/${SKILL_NAME:?}"
  cp -r "$SKILL_SRC" "$dst/$SKILL_NAME"
}

prepare_node() {
  local i=$1 ip=${HOST[$1]} name=${NAME[$1]} target="${NUSER[$1]}@${HOST[$1]}" rtmp upd creds mcp_user mcp_pass
  local copy_id=(-p "${SSH_PORT[$1]}" -o StrictHostKeyChecking=accept-new)
  if [[ -n ${KEY[i]} ]]; then copy_id+=(-i "${KEY[i]}.pub"); fi
  log "[$name] Checking key-based SSH connectivity"
  if ! nssh "$i" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$target" true 2>/dev/null; then
    log "[$name] SSH check failed; installing public key (enter the node password in the terminal)"
    run_stage "[$name] Install SSH public key" ssh-copy-id "${copy_id[@]}" "$target"
  fi
  log "[$name] SSH ready; creating remote workspace and uploading helpers"

  rtmp=$(nssh "$i" "$target" mktemp -d)
  [[ $rtmp =~ ^/[A-Za-z0-9._/-]+$ ]] || die "[$name] unexpected remote temp dir"
  nscp "$i" "$LOCAL_TMP/node-prepare.sh" "$LOCAL_TMP/env-merge.sh" "$target:$rtmp/"
  local source_args=(node_clone - - -)
  if [[ ${SOURCE_DELIVERY:-node_clone} == central_copy ]]; then
    log "[$name] Transferring centrally prepared app source (commit=$SOURCE_COMMIT)"
    nscp "$i" "$SOURCE_BUNDLE" "$target:$rtmp/source.bundle"
    source_args=(central_copy "$rtmp/source.bundle" "$SOURCE_SHA256" "$SOURCE_COMMIT")
  fi
  run_stage "[$name] Packages, Docker group, and app checkout" \
    nssh "$i" -t "$target" bash "$rtmp/node-prepare.sh" "$REPO_URL" "$REPO_BRANCH" "$REMOTE_ROOT" "$APP_SUBDIR" "${source_args[@]}" "${FLEET_CLEAN_CHECKOUT:-false}"
  log "[$name] Verifying Docker access in a new SSH session"
  nssh "$i" "$target" docker info >/dev/null 2>&1 || die "[$name] ${NUSER[i]} cannot use Docker on $ip"

  log "[$name] Preparing missing app credentials (values will not be logged)"
  upd="$LOCAL_TMP/$name.updates"
  {
    for k in "${USER_KEYS[@]}"; do printf 'fill %s %s\n' "$k" "$(rand_user)"; done
    for k in "${PASS_KEYS[@]}"; do printf 'fill %s %s\n' "$k" "$(rand_pass)"; done
    if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
      python3 - <<'PY'
import json, os
for key, value in json.loads(os.environ["ENV_UPDATES_JSON"]).items():
    print(f"set {key} {value}")
PY
    else
      printf 'set HOST_IP 127.0.0.1\n'
    fi
    if [[ ${SKIP[i]} == true ]]; then printf 'set PLATFORM_CHECK false\n'; fi
  } > "$upd"
  nscp "$i" "$upd" "$target:$rtmp/updates"
  rm -f "$upd"
  run_stage "[$name] Apply app environment updates" \
    nssh "$i" "$target" bash "$rtmp/env-merge.sh" "$APP_REL/.env" "$rtmp/updates"
  log "[$name] Removing remote temporary files"
  nssh "$i" "$target" rm -rf "$rtmp"

  if [[ $MCP_AUTH_TYPE == basic ]]; then
    log "[$name] Saving MCP authentication on central host (values will not be logged)"
    creds=$(nssh "$i" "$target" grep -E "'^($MCP_USER_KEY|$MCP_PASS_KEY)='" "$APP_REL/.env")
    mcp_user=$(sed -n "s/^$MCP_USER_KEY=//p" <<<"$creds" | tail -n 1)
    mcp_pass=$(sed -n "s/^$MCP_PASS_KEY=//p" <<<"$creds" | tail -n 1)
    [[ -n $mcp_user && -n $mcp_pass ]] || die "[$name] MCP credentials missing in the node's .env"
    set_central_env "${name^^}_MCP_BASIC" "$(printf '%s:%s' "$mcp_user" "$mcp_pass" | base64 -w0)"
  elif [[ $MCP_AUTH_TYPE == bearer ]]; then
    log "[$name] Saving MCP token on central host (value will not be logged)"
    creds=$(nssh "$i" "$target" grep -E "'^$MCP_TOKEN_KEY='" "$APP_REL/.env")
    mcp_pass=$(sed -n "s/^$MCP_TOKEN_KEY=//p" <<<"$creds" | tail -n 1)
    [[ -n $mcp_pass ]] || die "[$name] MCP token missing in the node's .env"
    [[ $mcp_pass =~ ^[A-Za-z0-9._~+/-]+=*$ ]] || die "[$name] MCP bearer token has an unsupported format"
    set_central_env "${name^^}_MCP_TOKEN" "$mcp_pass"
  fi
}

deploy_node() {
  local p=$1 file=$2 started=$SECONDS result=0
  log "START: Deployment and smoke check" > "$file" 2>&1
  if hermes -p "$p" chat -s "$SKILL_NAME" --oneshot -q "$DEPLOY_PROMPT" >> "$file" 2>&1; then
    log "DONE: Deployment and smoke check (elapsed=$((SECONDS - started))s)" >> "$file" 2>&1
  else
    result=$?
    log "ERROR: Deployment and smoke check (exit=$result, elapsed=$((SECONDS - started))s)" >> "$file" 2>&1
  fi
  return "$result"
}

deploy_all() {
  local i n p pid result active next_report=$((SECONDS + 30))
  local log_dir="$HOME/.hermes/logs/weld-fleet" pids=() nodes=()
  install -d "$log_dir"
  for i in "${!NAME[@]}"; do
    n=${NAME[i]} p=$(profile_of "${NAME[i]}")
    if $INTERACTIVE; then
      log "[$p] Interactive deployment; enter /quit when it finishes"
      if run_stage "[$n] Interactive deployment" \
        hermes -p "$p" chat -s "$SKILL_NAME" -q "$DEPLOY_PROMPT"; then
        log "[$n] Hermes chat completed; MCP readiness will be checked separately"
      else
        result=$?
        log "WARN: [$n] Hermes chat exited with $result; continuing to MCP readiness check"
        printf '%s\n' "$result" > "$LOCAL_TMP/$n.deploy-failed"
      fi
    else
      log "[$p] Deploying skill $SKILL_NAME in the background (log: $log_dir/$n.deploy.log)"
      run_stage "[$n] Deployment (log: $log_dir/$n.deploy.log)" deploy_node "$p" "$log_dir/$n.deploy.log" &
      pids+=("$!")
      nodes+=("$n")
    fi
  done
  while :; do
    active=()
    for i in "${!pids[@]}"; do
      if kill -0 "${pids[i]}" 2>/dev/null; then active+=("${nodes[i]}"); fi
    done
    (( ${#active[@]} )) || break
    if (( SECONDS >= next_report )); then
      log "WAIT: Deployment still running on ${active[*]}; follow $log_dir/<node>.deploy.log"
      next_report=$((SECONDS + 30))
    fi
    sleep 5
  done
  # The MCP check in connect_node decides success, not the agent's exit code.
  for i in "${!pids[@]}"; do
    pid=${pids[i]}
    if wait "$pid"; then
      log "[${nodes[i]}] Hermes deployment completed; MCP readiness will be checked separately"
    else
      result=$?
      log "WARN: [${nodes[i]}] Deployment exited with $result; see $log_dir/${nodes[i]}.deploy.log; continuing to MCP readiness check"
      printf '%s\n' "$result" > "$LOCAL_TMP/${nodes[i]}.deploy-failed"
    fi
  done
}

connect_node() {
  local i=$1 ip=${HOST[$1]} name=${NAME[$1]} target="${NUSER[$1]}@${HOST[$1]}" port=${LPORT[$1]}
  local cert="$HOME/.hermes/certs/${NAME[$1]}.pem" url="$MCP_SCHEME://localhost:${LPORT[$1]}$MCP_PATH" code=000
  local attempt ready_started tls_args=()
  node_opts "$i" -p
  # systemd splits $SSH_OPTS on spaces; all values were validated to contain none.
  printf 'LOCAL_PORT=%s\nREMOTE_PORT=%s\nNODE=%s\nSSH_OPTS=%s\n' "$port" "$REMOTE_PORT" "$target" "${NODE_OPTS[*]}" \
    > "$HOME/.config/weld-tunnels/$name.env"
  log "[$name] Starting SSH tunnel on local port $port"
  systemctl --user enable -q "weld-tunnel@$name"
  systemctl --user restart "weld-tunnel@$name"

  # Refresh the pin over authenticated SSH, because app certificates may change on redeploy.
  install -d -m 0700 "$HOME/.hermes/certs"
  if [[ $MCP_SCHEME == https ]]; then
    log "[$name] Fetching and validating current MCP certificate over SSH"
    if [[ -n $MCP_CERT_CONTAINER ]]; then
      nssh "$i" "$target" docker exec "$MCP_CERT_CONTAINER" cat "$MCP_CERT_PATH" > "$cert.tmp" \
        || die "[$name] cannot fetch MCP certificate"
    else
      nssh "$i" "$target" cat "$MCP_CERT_PATH" > "$cert.tmp" \
        || die "[$name] cannot fetch MCP certificate"
    fi
    openssl x509 -in "$cert.tmp" -noout
    mv "$cert.tmp" "$cert"
    tls_args=(--cacert "$cert")
  fi

  ready_started=$SECONDS
  log "[$name] Waiting for MCP tools/list readiness (up to 60 attempts)"
  for attempt in {1..60}; do
    # Authenticated endpoints are verified by Hermes below; do not put secrets in curl's argv.
    code=$(curl -s --connect-timeout 5 --max-time 15 "${tls_args[@]}" -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' || true)
    [[ $code == 200 || ( $MCP_AUTH_TYPE != none && $code == 401 ) ]] && break
    if (( attempt == 1 || attempt % 6 == 0 )); then
      log "WAIT: [$name] MCP not ready (attempt=$attempt/60, HTTP=$code, elapsed=$((SECONDS - ready_started))s)"
    fi
    sleep 5
  done
  [[ $code == 200 || ( $MCP_AUTH_TYPE != none && $code == 401 ) ]] || die "[$name] $url not ready (HTTP $code)"
  log "[$name] MCP endpoint responding (HTTP=$code, attempt=$attempt/60, elapsed=$((SECONDS - ready_started))s); verifying with Hermes next"

  log "[$name] Registering MCP URL, pinned certificate, credential reference, and tool allow-list"
  hermes config set "mcp_servers.$name.url" "$url"
  if [[ $MCP_SCHEME == https ]]; then
    hermes config set "mcp_servers.$name.ssl_verify" "$cert"
  else
    hermes config set "mcp_servers.$name.ssl_verify" true
  fi
  case $MCP_AUTH_TYPE in
    basic) hermes config set "mcp_servers.$name.headers.Authorization" "Basic \${${name^^}_MCP_BASIC}" ;;
    bearer) hermes config set "mcp_servers.$name.headers.Authorization" "Bearer \${${name^^}_MCP_TOKEN}" ;;
    none) hermes config set "mcp_servers.$name.headers" '{}' ;;
  esac
  hermes config set "mcp_servers.$name.tools.include" "$MCP_TOOLS"
  run_stage "[$name] Hermes MCP verification" hermes mcp test "$name" >/dev/null
}

ensure_user_systemd() {
  if systemctl --user show-environment >/dev/null 2>&1; then
    return 0
  fi
  local runtime_dir="/run/user/$(id -u)"
  if test -S "$runtime_dir/bus" && test -O "$runtime_dir" && test -O "$runtime_dir/bus"; then
    export XDG_RUNTIME_DIR="$runtime_dir"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
    if systemctl --user show-environment >/dev/null; then
      log "Recovered systemd user-session environment from $runtime_dir"
      return 0
    fi
  elif ! systemctl --user show-environment >/dev/null; then
    log "No existing user-owned systemd bus socket at $runtime_dir/bus"
  fi
  die "systemd user services are unavailable for UID $(id -u). Run from a normal login/SSH session as the central-host user, not via sudo or a container. If needed, ask an administrator to run loginctl enable-linger for that user, then log in again."
}

LOCAL_TMP=${FLEET_STATE_DIR:-$(mktemp -d)}
if [[ $FLEET_STAGE == all || $FLEET_STAGE == prepare ]]; then
stage_started=$SECONDS
log "START: Central host prerequisites and SSH keys"
for c in hermes ssh scp ssh-copy-id ssh-keygen curl openssl git base64 systemctl loginctl; do
  command -v "$c" >/dev/null || die "missing on this host: $c"
done
ensure_user_systemd
install -d -m 0700 "$HOME/.hermes" "$HOME/.ssh"
if ! compgen -G "$HOME/.ssh/id_*.pub" >/dev/null; then
  log "Creating default SSH key (private key contents will not be logged)"
  ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
fi
for i in "${!KEY[@]}"; do
  k=${KEY[i]}
  [[ -n $k ]] || continue
  if [[ ! -e $k ]]; then
    log "[${NAME[i]}] Creating configured SSH key (private key contents will not be logged)"
    install -d -m 0700 "$(dirname "$k")"
    ssh-keygen -q -t ed25519 -N '' -C "weld-fleet@$(hostname)" -f "$k"
  fi
  [[ -f $k.pub ]] || die "[${NAME[i]}] public key $k.pub not found"
done
log "DONE: Central host prerequisites and SSH keys (elapsed=$((SECONDS - stage_started))s)"

stage_started=$SECONDS
log "START: Acquire $SKILL_NAME skill"
if [[ -z ${SKILL_SRC:-} ]]; then
  cache="$HOME/.cache/weld-fleet/${REMOTE_ROOT}-${SKILL_NAME}"
  if [[ -d $cache/.git ]]; then
    log "Updating cached skill checkout"
    git -C "$cache" fetch -q "$SKILL_REPO_URL" "$SKILL_REPO_REF"
    git -C "$cache" checkout -q -f -B "$SKILL_REPO_REF" FETCH_HEAD
  else
    log "Cloning skill source (this may take several minutes)"
    git clone -q --filter=blob:none --sparse --branch "$SKILL_REPO_REF" "$SKILL_REPO_URL" "$cache"
  fi
  git -C "$cache" sparse-checkout set "$SKILL_PATH"
  SKILL_SRC="$cache/$SKILL_PATH"
else
  log "Using supplied local skill directory"
fi
[[ -f $SKILL_SRC/SKILL.md ]] || die "$SKILL_NAME skill not found at $SKILL_SRC"
if [[ ${FLEET_RECIPE_MODE:-} == 1 ]]; then
  python3 - "$SKILL_SRC/SKILL.md" "$SKILL_NAME" <<'PY'
import sys, yaml
from pathlib import Path
try:
    content = Path(sys.argv[1]).read_text()
    parts = content.split("---", 2)
    metadata = yaml.safe_load(parts[1]) if content.startswith("---\n") and len(parts) == 3 else None
    if not isinstance(metadata, dict) or metadata.get("name") != sys.argv[2]:
        sys.exit("ERROR: SKILL.md frontmatter name must match the configured skill name")
except (OSError, yaml.YAMLError):
    sys.exit("ERROR: cannot read skill metadata")
PY
fi
log "DONE: Acquire $SKILL_NAME skill (elapsed=$((SECONDS - stage_started))s)"

run_stage "Write remote helper scripts" write_helpers
run_stage "Install SSH tunnel service template" write_tunnel_unit

# Profiles first, so they don't clone MCP credentials stored for other nodes.
for i in "${!NAME[@]}"; do run_stage "[${NAME[i]}] Configure Hermes profile" setup_profile "$i"; done
for i in "${!NAME[@]}"; do run_stage "[${NAME[i]}] Prepare node" prepare_node "$i"; done
fi
[[ $FLEET_STAGE != prepare ]] || exit 0
if [[ $FLEET_STAGE == all || $FLEET_STAGE == deploy ]]; then
if $DEPLOY; then
  run_stage "Deploy apps across fleet" deploy_all
else
  log "SKIP: App deployment (--no-deploy); checking existing MCP servers"
fi
fi
[[ $FLEET_STAGE != deploy ]] || exit 0
ensure_user_systemd

declare -A status connection_time
rc=0
for i in "${!NAME[@]}"; do
  log "[${NAME[i]}] Connecting the MCP server"
  # Run in a background job so a failure on one node doesn't stop the others.
  stage_started=$SECONDS
  run_stage "[${NAME[i]}] Connect MCP server" connect_node "$i" &
  if wait "$!"; then status[$i]=connected; else status[$i]="not connected"; rc=1; fi
  if [[ ${FLEET_RECIPE_MODE:-} == 1 && -f $LOCAL_TMP/${NAME[i]}.deploy-failed ]]; then
    status[$i]="deploy failed"
    rc=1
  fi
  connection_time[$i]=$((SECONDS - stage_started))
done

log "Summary"
printf '%-11s %-15s %-12s %-29s %-14s %s\n' NODE HOST PROFILE "MCP URL" STATUS "CONNECT TIME"
for i in "${!NAME[@]}"; do
  printf '%-11s %-15s %-12s %-29s %-14s %ss\n' "${NAME[i]}" "${HOST[i]}" "$(profile_of "${NAME[i]}")" \
    "$MCP_SCHEME://localhost:${LPORT[i]}$MCP_PATH" "${status[$i]}" "${connection_time[$i]}"
done
[[ $rc -eq 0 ]] || log "Deployment logs: $HOME/.hermes/logs/weld-fleet/"
exit "$rc"
