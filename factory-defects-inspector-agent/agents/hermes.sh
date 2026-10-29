#!/usr/bin/env bash
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Hermes implementation of the fleet-setup.sh agent harness adapter.
#
# An adapter encapsulates every operation that depends on the agent harness;
# fleet-setup.sh selects one via HARNESS_AGENT (agents/<name>.sh) and calls
# only this contract:
#
#   AGENT_LABEL                       Human-readable harness name for logs
#   agent_capabilities                Prints optional capabilities, one per
#                                     line. "deploy" = the adapter supports
#                                     agentic deployment (the agent_context_*,
#                                     agent_skill_install, and agent_task_run*
#                                     functions below). Adapters without it
#                                     can only serve the --no-deploy flow:
#                                     node preparation, tunnels, and MCP
#                                     registration for an already-deployed
#                                     fleet, which need just the baseline
#                                     functions (init, dirs, env, MCP).
#   agent_required_commands           Prints required binaries, one per line
#   agent_init                        Creates the harness state directory
#   agent_log_dir                     Prints the fleet deployment log directory
#   agent_cert_dir                    Prints the pinned-certificate directory
#   agent_env_set KEY VALUE           Stores a secret for config references
#   agent_context_recreate NAME DESC  (Re)creates an isolated context cloned
#                                     from the central/default configuration
#   agent_context_set_ssh NAME HOST USER PORT [KEY]
#                                     Points the context's terminal at a node
#   agent_context_set_policy NAME POLICY
#                                     Sets the command approval policy
#   agent_skill_install NAME SKILL_NAME SKILL_SRC
#                                     Installs a skill into the context
#   agent_task_run NAME SKILL PROMPT  Runs a one-shot, non-interactive task;
#                                     exit code reports the task outcome
#   agent_task_run_interactive NAME SKILL PROMPT
#                                     Same, attached to the user's terminal
#   agent_mcp_register NAME URL SSL_VERIFY AUTH_TYPE TOOLS_JSON
#                                     Registers an MCP server with the central
#                                     agent; credentials are referenced from
#                                     agent_env_set storage, never inlined
#   agent_mcp_verify NAME             Verifies the registered MCP server
#
# This file is sourced by fleet-setup.sh, which provides log() and die().
# In Hermes terms a "context" is a profile: an isolated Hermes home under
# ~/.hermes/profiles/<name> whose terminal runs commands on one node over SSH.

AGENT_LABEL='Hermes'
AGENT_STATE_DIR="$HOME/.hermes"

agent_required_commands() { printf 'hermes\n'; }

agent_capabilities() { printf 'deploy\n'; }

agent_init() { install -d -m 0700 "$AGENT_STATE_DIR"; }

agent_log_dir() { printf '%s/logs/weld-fleet' "$AGENT_STATE_DIR"; }

agent_cert_dir() { printf '%s/certs' "$AGENT_STATE_DIR"; }

# Hermes resolves ${VAR} references in config.yaml from its own .env file.
agent_env_set() {
  local f="$AGENT_STATE_DIR/.env" tmp
  tmp=$(mktemp "$f.XXXXXX")
  { grep -v "^$1=" "$f" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
  mv "$tmp" "$f"
}

agent_context_recreate() {
  local name=$1 description=$2 profiles
  profiles=$(hermes profile list 2>/dev/null || true)
  if awk -v p="$name" '{ for (i = 1; i <= NF; i++) if ($i == p) found = 1 } END { exit !found }' <<<"$profiles"; then
    # Recreate rather than reuse: --clone snapshots the default profile only at
    # creation time, so a reused profile would silently keep the model/provider
    # configuration of an older default (e.g. from before a backend change).
    log "[$name] Removing existing $AGENT_LABEL profile (it is recreated from the current default profile)"
    hermes profile delete "$name" </dev/null >/dev/null 2>&1 || rm -rf "$AGENT_STATE_DIR/profiles/${name:?}"
  fi
  log "[$name] Creating $AGENT_LABEL profile from the current default profile"
  hermes profile create "$name" --clone --description "$description"
  # Node contexts must not inherit the central profile's MCP registrations.
  hermes -p "$name" config unset mcp_servers >/dev/null 2>&1 || true
}

agent_context_set_ssh() {
  local name=$1 host=$2 user=$3 port=$4 key=${5:-}
  hermes -p "$name" config set terminal.backend ssh
  hermes -p "$name" config set TERMINAL_SSH_HOST "$host"
  hermes -p "$name" config set TERMINAL_SSH_USER "$user"
  hermes -p "$name" config set TERMINAL_SSH_PORT "$port"
  if [[ -n $key ]]; then
    hermes -p "$name" config set TERMINAL_SSH_KEY "$key"
  else
    hermes -p "$name" config unset TERMINAL_SSH_KEY >/dev/null 2>&1 || true
  fi
  hermes -p "$name" config set terminal.timeout 3600
}

agent_context_set_policy() {
  hermes -p "$1" config set approvals.smart_policy "$2"
}

agent_skill_install() {
  local name=$1 skill_name=$2 skill_src=$3 dst
  dst="$AGENT_STATE_DIR/profiles/$name/skills/devops"
  install -d "$dst"
  rm -rf "${dst:?}/${skill_name:?}"
  cp -r "$skill_src" "$dst/$skill_name"
}

agent_task_run() {
  hermes -p "$1" chat -s "$2" --oneshot -q "$3"
}

agent_task_run_interactive() {
  hermes -p "$1" chat -s "$2" -q "$3"
}

agent_mcp_register() {
  local name=$1 url=$2 ssl_verify=$3 auth_type=$4 tools_json=$5
  hermes config set "mcp_servers.$name.url" "$url"
  hermes config set "mcp_servers.$name.ssl_verify" "$ssl_verify"
  # ${VAR} references are resolved by Hermes from agent_env_set storage, so
  # credential values never appear in the config file or process arguments.
  case $auth_type in
    basic) hermes config set "mcp_servers.$name.headers.Authorization" "Basic \${${name^^}_MCP_BASIC}" ;;
    bearer) hermes config set "mcp_servers.$name.headers.Authorization" "Bearer \${${name^^}_MCP_TOKEN}" ;;
    none) hermes config set "mcp_servers.$name.headers" '{}' ;;
    *) die "[$name] unsupported MCP auth type: $auth_type" ;;
  esac
  hermes config set "mcp_servers.$name.tools.include" "$tools_json"
}

agent_mcp_verify() {
  hermes mcp test "$1" >/dev/null
}
