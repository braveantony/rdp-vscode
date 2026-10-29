#!/usr/bin/env bash
# Smoke tests for the rdp-vscode image: bash test/image/smoke.test.sh <image>
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
IMG=${1:?usage: smoke.test.sh <image>}
arg() { sed -n "s/^ARG $1=//p" images/rdp-vscode/Dockerfile; }
run() { podman run --rm --entrypoint /bin/sh "$IMG" -c "$1"; }

say versions
want=$(arg VSCODIUM_VERSION)
got=$(podman run --rm --user 65534 --entrypoint /bin/sh "$IMG" -c 'HOME=/tmp codium --version 2>/dev/null | head -1')
[ -n "$want" ] && [ "$got" = "$want" ] && pass "codium $got" || bad "codium version: want '$want' got '$got'"

say vsix
ors=$(arg OPEN_REMOTE_SSH_VERSION); zh=$(arg ZH_HANT_VERSION)
for f in "jeanp413.open-remote-ssh-$ors.vsix" "ms-ceintl.vscode-language-pack-zh-hant-$zh.vsix"; do
  run "test -s /opt/rdp-vscode/vsix/$f" && pass "$f" || bad "missing /opt/rdp-vscode/vsix/$f"
done
run 'test ! -e /etc/skel/.vscode-oss' && pass "no /etc/skel/.vscode-oss" || bad "/etc/skel/.vscode-oss exists"

say commands
for c in xrdp xrdp-sesman tini openbox dbus-launch ssh; do
  run "command -v $c >/dev/null" && pass "$c" || bad "command not found: $c"
done

say locale-fonts
[ -n "$(run 'fc-list :lang=zh-tw')" ] && pass "zh-tw fonts" || bad "no zh-tw fonts"
run 'locale -a | grep -qx zh_TW.utf8' && pass "zh_TW.utf8 locale" || bad "zh_TW.utf8 locale missing"

say monospace-font
# entrypoint.sh writes font-config.sh's output to /etc/fonts/local.conf
mono() { podman run --rm -e "VSCODIUM_FONT=$1" --entrypoint /bin/sh "$IMG" -c \
  '/opt/rdp-vscode/font-config.sh > /etc/fonts/local.conf 2>/dev/null && fc-match -f "%{family[0]}" monospace'; }
for kv in "jetbrains-mono=JetBrains Mono" "cascadia-code=Cascadia Code" "noto=Noto Sans Mono CJK TC"; do
  got=$(mono "${kv%%=*}")
  [ "$got" = "${kv#*=}" ] && pass "monospace $kv" || bad "monospace ${kv%%=*}: got '$got'"
done

say xrdp-config
run '! grep -q "^\[Xvnc\]" /etc/xrdp/xrdp.ini' && pass "no [Xvnc]" || bad "[Xvnc] section present"
for kv in rdpdr=false rdpsnd=false; do
  run "grep -qx '$kv' /etc/xrdp/xrdp.ini" && pass "xrdp.ini $kv" || bad "xrdp.ini missing $kv"
done
for kv in Policy=Separate KillDisconnected=true DisconnectedTimeLimit=120 AllowRootLogin=false; do
  run "grep -qx '$kv' /etc/xrdp/sesman.ini" && pass "sesman.ini $kv" || bad "sesman.ini missing $kv"
done

say no-baked-keys
for f in key.pem cert.pem rsakeys.ini; do
  run "test ! -e /etc/xrdp/$f" && pass "no /etc/xrdp/$f" || bad "/etc/xrdp/$f baked into image"
done

say ssh-include
run 'grep -qxF "Include /etc/ssh/ssh_config.d/*.conf" /etc/ssh/ssh_config' && pass "ssh_config Include" || bad "ssh_config has no Include"

say scripts
for f in ssh-config.sh font-config.sh; do
  run "test -x /opt/rdp-vscode/$f" && pass "$f" || bad "/opt/rdp-vscode/$f missing"
done

finish
