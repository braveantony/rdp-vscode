#!/usr/bin/env bash
# Unit tests for images/rdp-vscode/rootfs/opt/rdp-vscode/session-env.sh
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
GEN=images/rdp-vscode/rootfs/opt/rdp-vscode/session-env.sh
unset VSCODIUM_LOCALE SSH_AUTO_CONNECT SSH_HOST_ALIAS SSH_REMOTE_FOLDER SSH_USER

# value_of <session.env text> <name>: the value after sourcing it like startwm.sh
value_of() { bash -c '. /dev/stdin; printf %s "${!1}"' _ "$2" <<<"$1"; }

check() {  # check <name> <var> <want> [VAR=value...]: run the generator with the given env
  local name=$1 var=$2 want=$3 out got
  shift 3
  out=$(env "$@" bash "$GEN" 2>/dev/null)
  got=$(value_of "$out" "$var")
  [ "$got" = "$want" ] && pass "$name" || bad "$name: want $var='$want' got '$got' in: $out"
}

say defaults
check "auto-connect off by default" SSH_AUTO_CONNECT false
check "locale zh-tw" VSCODIUM_LOCALE zh-tw
check "alias tkadm" SSH_HOST_ALIAS tkadm
check "folder /home/bigred" SSH_REMOTE_FOLDER /home/bigred

say auto-connect
check "true" SSH_AUTO_CONNECT true SSH_AUTO_CONNECT=true
check "false" SSH_AUTO_CONNECT false SSH_AUTO_CONNECT=false
check "empty is false" SSH_AUTO_CONNECT false SSH_AUTO_CONNECT=
check "garbage is false" SSH_AUTO_CONNECT false SSH_AUTO_CONNECT=yes
err=$(SSH_AUTO_CONNECT=yes bash "$GEN" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && grep -q '^\[entrypoint\] invalid SSH_AUTO_CONNECT: yes' <<<"$err" \
  && pass "garbage warns" || bad "garbage: rc=$rc err=$err"
err=$(SSH_AUTO_CONNECT=true bash "$GEN" 2>&1 >/dev/null)
[ -z "$err" ] && pass "true does not warn" || bad "true warns: $err"

say overrides
check "empty alias falls back to tkadm" SSH_HOST_ALIAS tkadm SSH_HOST_ALIAS=
check "alias lab" SSH_HOST_ALIAS lab SSH_HOST_ALIAS=lab
check "folder follows SSH_USER" SSH_REMOTE_FOLDER /home/alice SSH_USER=alice
check "explicit folder" SSH_REMOTE_FOLDER '/srv/my app' 'SSH_REMOTE_FOLDER=/srv/my app'
check "locale en" VSCODIUM_LOCALE en VSCODIUM_LOCALE=en

finish
