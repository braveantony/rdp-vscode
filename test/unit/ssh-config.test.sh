#!/usr/bin/env bash
# Unit tests for images/rdp-vscode/rootfs/opt/rdp-vscode/ssh-config.sh
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
GEN=images/rdp-vscode/rootfs/opt/rdp-vscode/ssh-config.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export RDP_VSCODE_SSH_CONFIG="$TMP/missing"
unset SSH_HOST_ALIAS SSH_HOST SSH_PORT SSH_USER

expected_defaults='Host tkadm
  HostName tkadm.taroko
  Port 22100
  User bigred
  StrictHostKeyChecking accept-new
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  GSSAPIAuthentication no'

say defaults
out=$(bash "$GEN" 2>&1)
[ "$out" = "$expected_defaults" ] && pass defaults || bad "defaults: got: $out"

say env-override
out=$(SSH_HOST_ALIAS=lab SSH_HOST=10.0.0.5 SSH_PORT=22 SSH_USER=alice bash "$GEN" 2>&1)
for line in 'Host lab' '  HostName 10.0.0.5' '  Port 22' '  User alice'; do
  grep -qxF -- "$line" <<<"$out" && pass "env-override: $line" || bad "env-override: missing '$line' in: $out"
done

say configmap-wins
printf 'Host foo\n' > "$TMP/cm"
RDP_VSCODE_SSH_CONFIG="$TMP/cm" bash "$GEN" > "$TMP/out"
cmp -s "$TMP/cm" "$TMP/out" && pass configmap-wins || bad "configmap-wins: output differs"

say empty-configmap
: > "$TMP/empty"
out=$(RDP_VSCODE_SSH_CONFIG="$TMP/empty" bash "$GEN" 2>&1)
[ "$out" = "$expected_defaults" ] && pass empty-configmap || bad "empty-configmap: got: $out"

say bad-port
for p in abc 70000 0; do
  err=$(SSH_PORT=$p bash "$GEN" 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 1 ] && grep -q '^\[entrypoint\] invalid' <<<"$err" && pass "bad-port $p" || bad "bad-port $p: rc=$rc err=$err"
done

say bad-alias
err=$(SSH_HOST_ALIAS='a b' bash "$GEN" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 1 ] && grep -q '^\[entrypoint\] invalid' <<<"$err" && pass bad-alias || bad "bad-alias: rc=$rc err=$err"

finish
