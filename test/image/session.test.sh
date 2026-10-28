#!/usr/bin/env bash
# Session tests: log in over RDP with the e2e client and check the kiosk
# VSCodium session.  bash test/image/session.test.sh [image]
# Needs the tk8s cluster DNS (10.98.0.10) so tkadm.taroko resolves.
# Chromium keeps CJK font data in /dev/shm; the 64MB default is too small.
# shellcheck disable=SC1091,SC2015,SC2016  # pass() never fails; single-quoted scripts expand inside the container
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
IMG=${1:-localhost/rdp-vscode:dev}
CLIENT=localhost/rdp-vscode-e2e-client:dev
SRV=rdp-vscode-session-test
PORT=33391
OUT=$PWD/test/e2e/out
mkdir -p "$OUT"

cleanup() { podman rm -f "$SRV" rdp-vscode-client-1 rdp-vscode-client-2 rdp-vscode-client-3 >/dev/null 2>&1; }
trap cleanup EXIT
cleanup

podman build -q -t "$CLIENT" test/e2e/client >/dev/null || { bad "build e2e client"; finish; }

start_server() {  # start_server [podman run args...]
  podman rm -f "$SRV" >/dev/null 2>&1
  podman run -d --name "$SRV" --dns 10.98.0.10 --dns-search svc.tk8s.k8s \
    --shm-size=1g -e RDP_PASSWORD=bigred -p "$PORT:3389" "$@" "$IMG" >/dev/null
  for _ in $(seq 20); do nc -z 127.0.0.1 "$PORT" 2>/dev/null && return 0; sleep 1; done
  return 1
}
login() {  # login <n>: client n logs in as bigred on its own X display
  podman run -d --name "rdp-vscode-client-$1" --network host -v "$OUT:/out:Z" \
    "$CLIENT" "127.0.0.1:$PORT" bigred bigred "session-$1" ":9$1" >/dev/null
}
sx() { podman exec "$SRV" bash -c "$1"; }
# Main codium processes of bigred (no --type=, i.e. not renderer/helper processes)
codium_main() { sx 'ps -u bigred -o args= | grep "^/usr/share/codium/codium " | grep -v -- "--type=" || true'; }
wait_for() {  # wait_for <seconds> <bash condition>
  for _ in $(seq "$1"); do eval "$2" && return 0; sleep 1; done
  return 1
}
xorg_count() { sx 'ps -u bigred -o comm= | grep -c "^Xorg" || true'; }
sess_dirs() { sx 'ls -d /tmp/sess/*.1000 2>/dev/null || true'; }
EXT=/home/bigred/.vscode-oss/extensions

say setup
start_server && pass "server up" || { bad "server did not start"; finish; }
# Seed a stale Open Remote-SSH and a user-installed extension before the first login
sx "su bigred -c 'mkdir -p $EXT/jeanp413.open-remote-ssh-0.0.1 $EXT/foo.bar-1.0.0 &&
  echo {\\\"name\\\":\\\"open-remote-ssh\\\",\\\"publisher\\\":\\\"jeanp413\\\",\\\"version\\\":\\\"0.0.1\\\"} > $EXT/jeanp413.open-remote-ssh-0.0.1/package.json &&
  echo {\\\"name\\\":\\\"bar\\\",\\\"publisher\\\":\\\"foo\\\",\\\"version\\\":\\\"1.0.0\\\",\\\"engines\\\":{\\\"vscode\\\":\\\"*\\\"}} > $EXT/foo.bar-1.0.0/package.json'"

say kiosk
sx 'test -f /home/bigred/.config/openbox/rc.xml' && pass "rc.xml in home" || bad "rc.xml missing"
login 1
if wait_for 40 '[ -n "$(codium_main)" ]'; then
  args=$(codium_main)
  grep -Eq -- "--remote[= ]ssh-remote\+tkadm( .*)? /home/bigred" <<<"$args" && pass "auto remote ssh-remote+tkadm" || bad "no ssh-remote+tkadm in: $args"
  grep -Eq -- "--locale[= ]zh-tw" <<<"$args" && pass "--locale zh-tw" || bad "no --locale zh-tw in: $args"
else
  bad "no codium process within 40s"
fi
S1=$(sess_dirs)

say ext-sync
ver=$(sed -n 's/^ARG OPEN_REMOTE_SSH_VERSION=//p' images/rdp-vscode/Dockerfile)
zh=$(sed -n 's/^ARG ZH_HANT_VERSION=//p' images/rdp-vscode/Dockerfile)
listing1=$(sx "ls $EXT")
grep -qx "jeanp413.open-remote-ssh-0.0.1" <<<"$listing1" && bad "stale open-remote-ssh-0.0.1 kept" || pass "stale version removed"
grep -qx "jeanp413.open-remote-ssh-$ver" <<<"$listing1" && pass "open-remote-ssh-$ver installed" || bad "open-remote-ssh-$ver missing: $listing1"
grep -qx "ms-ceintl.vscode-language-pack-zh-hant-$zh" <<<"$listing1" && pass "zh-hant-$zh installed" || bad "zh-hant-$zh missing: $listing1"
grep -qx "foo.bar-1.0.0" <<<"$listing1" && pass "user extension kept" || bad "user extension foo.bar removed"
sum1=$(sx "cd $EXT && find . -printf '%p %s %T@\n' | sort | md5sum")

say settings-shared
d1=$(codium_main | grep -Eo -- '--user-data-dir[= ][^ ]*' | head -1 | cut -c17-)
sx "su bigred -c 'cp ~/.config/VSCodium/User/settings.json /tmp/settings.bak &&
  sed -i \"1a \\\"rdpVscodeTest.marker\\\": 42,\" ~/.config/VSCodium/User/settings.json'"
sx "grep -q rdpVscodeTest.marker $d1/User/settings.json" && pass "settings shared via $d1/User" || bad "marker not visible in $d1/User/settings.json"
sx "su bigred -c 'cp /tmp/settings.bak ~/.config/VSCodium/User/settings.json'"

say same-account-twice
login 2
if wait_for 40 '[ "$(codium_main | wc -l)" -ge 2 ]'; then
  [ "$(xorg_count)" -ge 2 ] && pass "two Xorg" || bad "Xorg count: $(xorg_count)"
  n=$(codium_main | grep -Eo -- '--user-data-dir[= ][^ ]*' | sort -u | wc -l)
  [ "$n" -eq 2 ] && pass "two distinct --user-data-dir" || bad "distinct user-data-dirs: $n"
else
  bad "second codium did not start within 40s"
fi
sum2=$(sx "cd $EXT && find . -printf '%p %s %T@\n' | sort | md5sum")
[ "$sum1" = "$sum2" ] && pass "ext-sync is idempotent on second login" || bad "extensions dir changed on second login"
S2=$(comm -13 <(echo "$S1") <(sess_dirs))

say disconnect-cleanup
if [ -n "$S2" ]; then
  podman rm -f rdp-vscode-client-2 >/dev/null
  if wait_for 150 '! sx "test -e $S2" && ! codium_main | grep -q -- "$S2/"'; then
    pass "disconnected session cleaned up ($S2)"
  else
    bad "after 150s: $S2 still exists or its codium still runs"
  fi
  [ -n "$(codium_main)" ] && pass "first session untouched" || bad "first session's codium is gone"
else
  bad "could not identify the second session dir"
fi

say close-logout
sx 'pkill -u bigred -f /usr/share/codium' || true
if wait_for 15 '[ "$(xorg_count)" -eq 0 ] && [ -z "$(sess_dirs)" ]'; then
  pass "closing VSCodium ends the session"
else
  bad "after 15s: Xorg=$(xorg_count) sess=$(sess_dirs)"
fi
podman rm -f rdp-vscode-client-1 >/dev/null

say locale-en
start_server -e VSCODIUM_LOCALE=en || bad "server (en) did not start"
login 3
if wait_for 40 '[ -n "$(codium_main)" ]'; then
  codium_main | grep -Eq -- "--locale[= ]en( |$)" && pass "--locale en" || bad "no --locale en in: $(codium_main)"
else
  bad "no codium process within 40s (en)"
fi

finish
