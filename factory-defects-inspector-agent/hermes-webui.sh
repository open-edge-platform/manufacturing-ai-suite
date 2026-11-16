#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Installs Hermes WebUI (https://github.com/nesquena/hermes-webui) natively on this host and runs it
# against the local Hermes Agent (~/.hermes). Password login is always on. By default it
# listens on 127.0.0.1 only.
#
# Usage: ./hermes-webui.sh [--host ADDR] [--no-proxy] [setup|install|persona|start|stop|restart|status|logs|proxy]
#   (default: start)
#   setup    install if needed, install the SOUL.md persona, then start the daemon and the HTTPS proxy
#   install  clone or update the pinned release and create .env (asks for a password, or generates
#            one when there is no terminal)
#   persona  copy this directory's SOUL.md into the Hermes home (an existing persona is backed up
#            to SOUL.md.backup.<timestamp> first; merge manual customizations from the backup)
#   start    install if needed, then start the daemon and the HTTPS proxy (restart does the same;
#            stop stops both)
#   proxy [start|stop|status]  run a user-level nginx HTTPS reverse proxy (self-signed certificate,
#            no root needed) in front of the WebUI, which stays on 127.0.0.1. start, setup and
#            restart run it by default when nginx and openssl are installed; otherwise they
#            skip it with a note.
#   Others pass through to the WebUI's ctl.sh.
#   --no-proxy  do not start the proxy with start, setup or restart (or set HERMES_WEBUI_PROXY=0)
#   --host ADDR  bind address: 127.0.0.1 (default), 0.0.0.0 (all interfaces), or one of this
#            host's IPv4 addresses; saved in .env and kept until set again. Equivalent to the
#            HERMES_WEBUI_HOST environment variable.
#
# Environment: HERMES_WEBUI_DIR (default ~/hermes-webui), HERMES_WEBUI_VERSION (default v0.52.492),
#              HERMES_WEBUI_PORT (default 8787), HERMES_WEBUI_HOST (see --host above),
#              HERMES_WEBUI_PROXY (default 1; 0 disables the proxy),
#              HERMES_WEBUI_PROXY_PORT (default 8443), HERMES_WEBUI_PROXY_BIND (default 0.0.0.0),
#              HERMES_WEBUI_PROXY_DIR (default ~/.hermes-webui-proxy).
set -euo pipefail

REPO_URL="https://github.com/nesquena/hermes-webui.git"
VERSION="${HERMES_WEBUI_VERSION:-v0.52.492}"
DIR="${HERMES_WEBUI_DIR:-$HOME/hermes-webui}"
PORT="${HERMES_WEBUI_PORT:-8787}"
REQ_HOST="${HERMES_WEBUI_HOST:-}"
PROXY_DIR="${HERMES_WEBUI_PROXY_DIR:-$HOME/.hermes-webui-proxy}"
PROXY_ENABLED="${HERMES_WEBUI_PROXY:-1}"
PROXY_PORT="${HERMES_WEBUI_PROXY_PORT:-8443}"
PROXY_BIND="${HERMES_WEBUI_PROXY_BIND:-0.0.0.0}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIND_CHANGED=0

die() { echo "error: $*" >&2; exit 1; }

[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "HERMES_WEBUI_VERSION must be a stable tag like v0.52.492"
[[ $PORT =~ ^[0-9]{4,5}$ ]] && (( PORT >= 1024 && PORT <= 65535 )) || die "HERMES_WEBUI_PORT must be 1024-65535"
[[ $PROXY_PORT =~ ^[0-9]{4,5}$ ]] && (( PROXY_PORT >= 1024 && PROXY_PORT <= 65535 )) \
  || die "HERMES_WEBUI_PROXY_PORT must be 1024-65535"
[[ $PROXY_BIND =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "HERMES_WEBUI_PROXY_BIND must be an IPv4 address"

check_prereqs() {
  command -v git >/dev/null || die "git is required"
  command -v python3 >/dev/null || die "python3 is required"
  command -v hermes >/dev/null || [[ -d $HERMES_HOME/hermes-agent ]] \
    || die "Hermes Agent not found; install it first (see hermes-setup.md)"
  [[ -f $HERMES_HOME/config.yaml ]] || die "$HERMES_HOME/config.yaml not found; run 'hermes setup' first"
}

install() {
  check_prereqs
  if [[ -d $DIR/.git ]]; then
    git -C "$DIR" diff --quiet && git -C "$DIR" diff --cached --quiet \
      || die "$DIR has local changes; commit or discard them first"
    git -C "$DIR" fetch --quiet --tags origin
  else
    [[ -e $DIR ]] && die "$DIR exists and is not a git clone"
    git clone --quiet "$REPO_URL" "$DIR"
  fi
  git -C "$DIR" -c advice.detachedHead=false checkout --quiet "refs/tags/$VERSION"
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

# Install the Factory Defects Inspector persona into the Hermes home. Never
# discards an existing persona: identical copies are a no-op, anything else is
# backed up with a timestamp so manual customizations can be merged back.
persona_install() {
  local src="$SCRIPT_DIR/SOUL.md" dest="$HERMES_HOME/SOUL.md" backup
  [[ -f $src ]] || die "persona template not found: $src"
  # "command": the external install(1), not this script's install() function.
  command install -d -m 0700 "$HERMES_HOME"
  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    echo "Persona already up to date: $dest"
    return 0
  fi
  if [[ -f $dest ]]; then
    # mktemp reserves a unique name, so updates within the same second
    # cannot overwrite an earlier backup.
    backup=$(mktemp "$dest.backup.$(date +%Y%m%dT%H%M%S).XXXXXX")
    cp -p "$dest" "$backup"
    echo "Backed up existing persona to $backup; merge any customizations you need from it"
  fi
  cp "$src" "$dest"
  chmod 600 "$dest"
  echo "Installed the Factory Defects Inspector persona at $dest (applies to new default-profile chats)"
}

env_value() { sed -n "s/^$1=//p" "$DIR/.env" | tail -1; }

# Decide the bind address, save it to .env, and export it (ctl.sh lets the shell environment win).
configure_bind() {
  local env_file="$DIR/.env" current host
  [[ -n $(env_value HERMES_WEBUI_PASSWORD) ]] || die "no HERMES_WEBUI_PASSWORD in $env_file; run '$0 install'"
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
  if [[ $host != "$current" ]]; then
    if grep -q '^HERMES_WEBUI_HOST=' "$env_file"; then
      sed -i "s/^HERMES_WEBUI_HOST=.*/HERMES_WEBUI_HOST=$host/" "$env_file"
    else
      printf 'HERMES_WEBUI_HOST=%s\n' "$host" >> "$env_file"
    fi
    BIND_CHANGED=1
  fi
  export HERMES_WEBUI_HOST="$host"
  if [[ $host != 127.0.0.1 ]]; then
    cat >&2 <<EOF
WARNING: Hermes WebUI will listen on $host (plain HTTP). The password and chats cross the network
unencrypted, and anyone who logs in gets a terminal and file access as $(id -un). Use it only on a
trusted network, limit the port with a firewall, and prefer SSH port forwarding or a TLS proxy.
EOF
  fi
}

wait_healthy() {
  local port host probe
  port="${HERMES_WEBUI_PORT:-$(env_value HERMES_WEBUI_PORT)}"
  port="${port:-$PORT}"
  host=$(env_value HERMES_WEBUI_HOST)
  case "$host" in 0.0.0.0 | 127.0.0.1 | "") probe=127.0.0.1 ;; *) probe=$host ;; esac
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://$probe:$port/health" 2>/dev/null; then
      echo "Hermes WebUI is up on $host:$port"
      case "$host" in
        127.0.0.1 | "")
          echo "  http://127.0.0.1:$port/"
          echo "  From another machine: ssh -N -L $port:127.0.0.1:$port $(id -un)@$(hostname)"
          ;;
        0.0.0.0)
          local ip
          for ip in 127.0.0.1 $(hostname -I); do
            [[ $ip == *:* ]] || echo "  http://$ip:$port/"
          done
          ;;
        *) echo "  http://$host:$port/" ;;
      esac
      return 0
    fi
    sleep 2
  done
  "$DIR/ctl.sh" logs --lines 40 --no-follow || true
  die "WebUI did not become healthy on port $port"
}

start_webui() {
  configure_bind
  if (( BIND_CHANGED )); then
    "$DIR/ctl.sh" restart   # apply the new bind address to a running instance
  else
    "$DIR/ctl.sh" start     # no-op if already running
  fi
  wait_healthy
}

proxy_running() {
  [[ -f $PROXY_DIR/nginx.pid ]] && kill -0 "$(cat "$PROXY_DIR/nginx.pid")" 2>/dev/null
}

proxy_start() {
  command -v nginx >/dev/null || die "nginx is required (for example: sudo apt install nginx)"
  command -v openssl >/dev/null || die "openssl is required"
  [[ -f $DIR/.env ]] || die "not installed; run '$0 install'"

  local up_host up_port ip san
  up_host=$(env_value HERMES_WEBUI_HOST)
  case "$up_host" in 0.0.0.0 | "") up_host=127.0.0.1 ;; esac
  up_port="${HERMES_WEBUI_PORT:-$(env_value HERMES_WEBUI_PORT)}"
  up_port="${up_port:-$PORT}"
  [[ $up_host == 127.0.0.1 ]] \
    || echo "WARNING: the WebUI listens on $up_host in plain HTTP; run '$0 --host 127.0.0.1 restart' so only the proxy is reachable." >&2

  command install -d -m 0700 "$PROXY_DIR"
  if [[ ! -f $PROXY_DIR/cert.pem || ! -f $PROXY_DIR/key.pem ]]; then
    san="DNS:localhost,DNS:$(hostname),IP:127.0.0.1"
    for ip in $(hostname -I); do [[ $ip == *:* ]] || san+=",IP:$ip"; done
    ( umask 077
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 \
        -subj "/CN=$(hostname)" -addext "subjectAltName=$san" \
        -keyout "$PROXY_DIR/key.pem" -out "$PROXY_DIR/cert.pem" )
    echo "Generated a self-signed certificate in $PROXY_DIR (valid 365 days)"
  fi

  cat > "$PROXY_DIR/nginx.conf" <<EOF
worker_processes 1;
pid $PROXY_DIR/nginx.pid;
error_log $PROXY_DIR/error.log warn;

events {}

http {
    access_log $PROXY_DIR/access.log;
    client_body_temp_path $PROXY_DIR/tmp-body;
    proxy_temp_path $PROXY_DIR/tmp-proxy;
    fastcgi_temp_path $PROXY_DIR/tmp-fastcgi;
    uwsgi_temp_path $PROXY_DIR/tmp-uwsgi;
    scgi_temp_path $PROXY_DIR/tmp-scgi;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen $PROXY_BIND:$PROXY_PORT ssl;
        server_name _;
        client_max_body_size 100M;

        ssl_certificate $PROXY_DIR/cert.pem;
        ssl_certificate_key $PROXY_DIR/key.pem;
        ssl_protocols TLSv1.3;
        ssl_session_tickets off;

        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options SAMEORIGIN;

        location / {
            proxy_pass http://$up_host:$up_port;
            proxy_http_version 1.1;
            proxy_set_header Host \$http_host;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }
    }
}
EOF

  local ngx=(nginx -p "$PROXY_DIR" -c "$PROXY_DIR/nginx.conf")
  # nginx >= 1.19.5 can override the compiled-in error log, which may not be writable.
  if nginx -h 2>&1 | grep -q -- '-e filename'; then ngx+=(-e "$PROXY_DIR/error.log"); fi
  "${ngx[@]}" -t
  if proxy_running; then
    kill -HUP "$(cat "$PROXY_DIR/nginx.pid")"
  else
    "${ngx[@]}"
  fi

  echo "HTTPS proxy is up (self-signed certificate; the browser shows a warning until you trust it):"
  if [[ $PROXY_BIND == 0.0.0.0 ]]; then
    for ip in 127.0.0.1 $(hostname -I); do
      [[ $ip == *:* ]] || echo "  https://$ip:$PROXY_PORT/"
    done
  else
    echo "  https://$PROXY_BIND:$PROXY_PORT/"
  fi
}

proxy_stop() {
  if proxy_running; then
    kill -QUIT "$(cat "$PROXY_DIR/nginx.pid")"
    echo "HTTPS proxy stopped"
  else
    echo "HTTPS proxy is not running"
  fi
}

proxy_cmd() {
  case "${1:-start}" in
    start) proxy_start ;;
    stop) proxy_stop ;;
    status) if proxy_running; then echo "HTTPS proxy is running on $PROXY_BIND:$PROXY_PORT"; else echo "HTTPS proxy is not running"; exit 1; fi ;;
    *) die "usage: $0 proxy [start|stop|status]" ;;
  esac
}

# Default-on proxy for start/setup/restart; missing nginx or openssl is a note, not an error.
proxy_auto() {
  [[ $PROXY_ENABLED == 1 ]] || return 0
  if command -v nginx >/dev/null && command -v openssl >/dev/null; then
    proxy_start
  else
    echo "Note: nginx or openssl is missing, so the HTTPS proxy was not started. Install both and run '$0 proxy'." >&2
  fi
}

ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --host) [[ $# -ge 2 ]] || die "--host needs an address"; REQ_HOST=$2; shift 2 ;;
    --no-proxy) PROXY_ENABLED=0; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

cmd="${1:-start}"
case "$cmd" in
  setup)
    install
    persona_install
    start_webui
    proxy_auto
    ;;
  install) install ;;
  persona) persona_install ;;
  start)
    [[ -d $DIR/.git && -f $DIR/.env ]] || install
    start_webui
    proxy_auto
    ;;
  restart)
    [[ -x $DIR/ctl.sh && -f $DIR/.env ]] || die "not installed; run '$0 install'"
    configure_bind
    "$DIR/ctl.sh" restart
    wait_healthy
    proxy_auto
    ;;
  stop | status | logs)
    [[ -x $DIR/ctl.sh ]] || die "not installed; run '$0 install'"
    shift || true
    "$DIR/ctl.sh" "$cmd" "$@"
    [[ $cmd != stop ]] || proxy_stop
    ;;
  proxy)
    shift || true
    proxy_cmd "$@"
    ;;
  *) sed -n '5,/^set /{/^set /!p}' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
