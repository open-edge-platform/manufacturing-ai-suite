#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Installs Hermes WebUI (https://github.com/nesquena/hermes-webui) natively on this host and runs it
# against the local Hermes Agent (~/.hermes). Password login is always on. It is served over HTTPS
# only, with a self-signed certificate generated in ~/.hermes/webui-tls. By default it listens on
# 127.0.0.1 only.
#
# Usage: ./hermes-webui.sh [--host ADDR] start|stop
#   start    install the pinned release if needed (asks for a password, or generates one when
#            there is no terminal), install the SOUL.md persona if the Hermes home has none,
#            create the TLS certificate if missing or expiring, then start the daemon (or
#            restart it when the release, bind address, or certificate changed)
#   stop     stop the daemon
#   --host ADDR  bind address: 127.0.0.1 (default), 0.0.0.0 (all interfaces), or one of this
#            host's IPv4 addresses; saved in .env and kept until set again. Equivalent to the
#            HERMES_WEBUI_HOST environment variable.
#
# Environment: HERMES_WEBUI_DIR (default ~/hermes-webui), HERMES_WEBUI_VERSION (default v0.52.492),
#              HERMES_WEBUI_PORT (default 8787), HERMES_WEBUI_HOST (see --host above).
set -euo pipefail

REPO_URL="https://github.com/nesquena/hermes-webui.git"
VERSION="${HERMES_WEBUI_VERSION:-v0.52.492}"
DIR="${HERMES_WEBUI_DIR:-$HOME/hermes-webui}"
PORT="${HERMES_WEBUI_PORT:-8787}"
REQ_HOST="${HERMES_WEBUI_HOST:-}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTART_NEEDED=0

die() { echo "error: $*" >&2; exit 1; }

[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "HERMES_WEBUI_VERSION must be a stable tag like v0.52.492"
[[ $PORT =~ ^[0-9]{4,5}$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "HERMES_WEBUI_PORT must be 1024-65535"

check_prereqs() {
  command -v git >/dev/null || die "git is required"
  command -v python3 >/dev/null || die "python3 is required"
  command -v hermes >/dev/null || [[ -d $HERMES_HOME/hermes-agent ]] \
    || die "Hermes Agent not found; install it first with the Agent Harness Installer (https://github.com/open-edge-platform/edge-ai-libraries/tree/release-2026.3.0/frameworks/agent-harness-install); see docs/user-guide/get-started/set-up-central-host.md"
  [[ -f $HERMES_HOME/config.yaml ]] || die "$HERMES_HOME/config.yaml not found; run 'hermes setup' first"
}

install() {
  check_prereqs
  local before
  before=$(git -C "$DIR" describe --tags --exact-match 2>/dev/null || true)
  if [[ -d $DIR/.git ]]; then
    git -C "$DIR" diff --quiet && git -C "$DIR" diff --cached --quiet \
      || die "$DIR has local changes; commit or discard them first"
    git -C "$DIR" fetch --quiet --tags origin
  else
    [[ -e $DIR ]] && die "$DIR exists and is not a git clone"
    git clone --quiet "$REPO_URL" "$DIR"
  fi
  git -C "$DIR" -c advice.detachedHead=false checkout --quiet "refs/tags/$VERSION"
  # ctl.sh start is a no-op for a running daemon, so a changed release needs an explicit restart.
  [[ $before == "$VERSION" ]] || RESTART_NEEDED=1
  echo "Hermes WebUI $VERSION in $DIR"

  local env_file="$DIR/.env"
  if [[ ! -f $env_file ]] || ! grep -q '^HERMES_WEBUI_PASSWORD=.' "$env_file"; then
    local pw pw2
    if [[ -t 0 ]]; then
      read -rsp "Choose a WebUI password (min 12 chars): " pw; echo
      read -rsp "Repeat it: " pw2; echo
      [[ $pw == "$pw2" ]] || die "passwords do not match"
      (( ${#pw} >= 12 )) || die "password too short"
      [[ $pw != *$'\n'* && $pw != *'"'* && $pw != *"'"* ]] || die "password must not contain quotes"
    else
      command -v openssl >/dev/null || die "openssl is required to generate a password"
      pw=$(openssl rand -hex 16)
      echo "No terminal: generated a random WebUI password. Read it with: grep PASSWORD $env_file"
    fi
    ( umask 077
      printf "HERMES_WEBUI_HOST=127.0.0.1\nHERMES_WEBUI_PORT=%s\nHERMES_WEBUI_PASSWORD='%s'\n" "$PORT" "$pw" > "$env_file" )
    unset pw pw2
    echo "Saved settings to $env_file (mode 600)"
  fi
  chmod 600 "$env_file"
}

# Never overwrites an existing persona, so manual customizations survive.
persona_install() {
  local src="$SCRIPT_DIR/SOUL.md" dest="$HERMES_HOME/SOUL.md"
  [[ -f $src ]] || die "persona template not found: $src"
  if [[ -f $dest ]]; then
    cmp -s "$src" "$dest" || echo "Keeping existing persona $dest (differs from $src)"
    return 0
  fi
  # "command": the external install(1), not this script's install() function.
  command install -d -m 0700 "$HERMES_HOME"
  ( umask 077; cp "$src" "$dest" )
  echo "Installed the Factory Defects Inspector persona at $dest (applies to new default-profile chats)"
}

env_value() { sed -n "s/^$1=//p" "$DIR/.env" | tail -1; }

# Write KEY=VALUE to .env; a changed value means a running daemon must restart.
set_env() {
  local key=$1 value=$2
  [[ $(env_value "$key") == "$value" ]] && return 0
  sed -i "/^$key=/d" "$DIR/.env"
  printf '%s=%s\n' "$key" "$value" >> "$DIR/.env"
  RESTART_NEEDED=1
}

# Create a self-signed certificate if missing or expiring within 30 days, and enable HTTPS in .env.
tls_install() {
  local tdir="$HERMES_HOME/webui-tls" ip san
  local cert="$tdir/cert.pem" key="$tdir/key.pem"
  command -v openssl >/dev/null || die "openssl is required for HTTPS"
  if [[ ! -f $cert || ! -f $key ]] || ! openssl x509 -checkend 2592000 -noout -in "$cert" >/dev/null; then
    san="DNS:localhost,DNS:$(hostname),IP:127.0.0.1"
    for ip in $(ip -4 -o addr show scope global | awk '{split($4, a, "/"); print a[1]}'); do
      san+=",IP:$ip"
    done
    command install -d -m 0700 "$tdir"
    ( umask 077
      openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 365 -subj "/CN=$(hostname)" \
        -addext "subjectAltName=$san" -keyout "$key" -out "$cert" 2>/dev/null )
    echo "Generated a self-signed certificate (365 days): $cert"
    RESTART_NEEDED=1
  fi
  # The server silently falls back to plain HTTP when it cannot load the pair, so refuse to start.
  openssl x509 -in "$cert" -noout 2>/dev/null && openssl pkey -in "$key" -noout 2>/dev/null \
    && [[ $(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null) == "$(openssl pkey -in "$key" -pubout 2>/dev/null)" ]] \
    || die "the certificate and key in $tdir are unreadable or do not match; delete the directory and run start again"
  set_env HERMES_WEBUI_TLS_CERT "'$cert'"
  set_env HERMES_WEBUI_TLS_KEY "'$key'"
}

# Decide the bind address, save it to .env, and export it (ctl.sh lets the shell environment win).
configure_bind() {
  local env_file="$DIR/.env" current host
  [[ -n $(env_value HERMES_WEBUI_PASSWORD) ]] || die "no HERMES_WEBUI_PASSWORD in $env_file"
  current=$(env_value HERMES_WEBUI_HOST)
  host="${REQ_HOST:-${current:-127.0.0.1}}"
  case "$host" in
    127.0.0.1 | 0.0.0.0) ;;
    *)
      [[ $host =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] \
        && ip -4 -o addr show | awk '{split($4, a, "/"); print a[1]}' | grep -qxF "$host" \
        || die "HERMES_WEBUI_HOST must be 127.0.0.1, 0.0.0.0, or an IPv4 address of this host"
      ;;
  esac
  set_env HERMES_WEBUI_HOST "$host"
  export HERMES_WEBUI_HOST="$host"
  if [[ $host != 127.0.0.1 ]]; then
    cat >&2 <<EOF
WARNING: Hermes WebUI will listen on $host over HTTPS with a self-signed certificate. Anyone who
logs in gets a terminal and file access as $(id -un). Use it only on a trusted network, limit the
port with a firewall, and import $HERMES_HOME/webui-tls/cert.pem on each client to trust it.
EOF
  fi
}

# The server falls back to plain HTTP if it cannot load the certificate; refuse that.
wait_healthy() {
  local port host probe
  port="${HERMES_WEBUI_PORT:-$(env_value HERMES_WEBUI_PORT)}"
  port="${port:-$PORT}"
  host=$(env_value HERMES_WEBUI_HOST)
  case "$host" in 0.0.0.0 | 127.0.0.1 | "") probe=127.0.0.1 ;; *) probe=$host ;; esac
  for _ in $(seq 1 30); do
    if curl -fsSk -o /dev/null "https://$probe:$port/health" 2>/dev/null; then
      echo "Hermes WebUI is up on $host:$port (HTTPS, self-signed certificate)"
      case "$host" in
        127.0.0.1 | "")
          echo "  https://127.0.0.1:$port/"
          echo "  From another machine: ssh -N -L $port:127.0.0.1:$port $(id -un)@$(hostname)"
          ;;
        0.0.0.0)
          local ip
          for ip in 127.0.0.1 $(hostname -I); do
            [[ $ip == *:* ]] || echo "  https://$ip:$port/"
          done
          ;;
        *) echo "  https://$host:$port/" ;;
      esac
      echo "  To trust the certificate, import $HERMES_HOME/webui-tls/cert.pem on each client."
      return 0
    fi
    sleep 2
  done
  if curl -fsS -o /dev/null "http://$probe:$port/health" 2>/dev/null; then
    "$DIR/ctl.sh" stop || true
    die "WebUI answered over plain HTTP (certificate not loaded); stopped it. Delete $HERMES_HOME/webui-tls and run start again"
  fi
  "$DIR/ctl.sh" logs --lines 40 --no-follow || true
  die "WebUI did not become healthy on port $port"
}

start_webui() {
  tls_install
  configure_bind
  if (( RESTART_NEEDED )); then
    "$DIR/ctl.sh" restart   # apply the new settings to a running instance
  else
    "$DIR/ctl.sh" start     # no-op if already running
  fi
  wait_healthy
}

ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --host) [[ $# -ge 2 ]] || die "--host needs an address"; REQ_HOST=$2; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "${1:-}" in
  start)
    # Re-run install when the checkout is missing, not at the pinned tag, or has no password.
    [[ -f $DIR/.env && $(git -C "$DIR" describe --tags --exact-match 2>/dev/null) == "$VERSION" ]] || install
    persona_install
    start_webui
    ;;
  stop)
    [[ -x $DIR/ctl.sh ]] || die "not installed; nothing to stop"
    "$DIR/ctl.sh" stop
    ;;
  *) sed -n '5,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
