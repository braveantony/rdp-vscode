#!/usr/bin/env bash
# Print the ssh_config used to reach the SSH target (tkadm by default).
# A non-empty ConfigMap file wins; otherwise the config is built from SSH_* env.
set -eu

cm=${RDP_VSCODE_SSH_CONFIG:-/etc/rdp-vscode/ssh/config}
if [ -s "$cm" ]; then
  cat "$cm"
  exit 0
fi

alias=${SSH_HOST_ALIAS:-tkadm}
host=${SSH_HOST:-tkadm.taroko}
port=${SSH_PORT:-22100}
user=${SSH_USER:-bigred}

case $port in
  '' | *[!0-9]*) echo "[entrypoint] invalid SSH_PORT: $port" >&2; exit 1 ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "[entrypoint] invalid SSH_PORT: $port" >&2
  exit 1
fi
case $alias in
  '' | *[[:space:]]*) echo "[entrypoint] invalid SSH_HOST_ALIAS: '$alias'" >&2; exit 1 ;;
esac

cat <<CFG
Host $alias
  HostName $host
  Port $port
  User $user
  StrictHostKeyChecking accept-new
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  GSSAPIAuthentication no
CFG
