#!/usr/bin/env bash
# Attached mode (RDP_MODE=attached): the container runs no xrdp. It waits on a
# unix socket and starts VSCodium for whoever asks, on a desktop that another
# container of the same pod provides.   bash test/image/attached.test.sh [image]
# The "desktop" here is a second container from the same image in standalone
# mode; in a real deployment it is rdp-firefox in workspace mode.
# Chromium keeps CJK font data in /dev/shm; the 64MB default is too small.
# shellcheck disable=SC1091,SC2015,SC2016  # pass() never fails; single-quoted scripts expand inside the container
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
IMG=${1:-localhost/rdp-vscode:dev}
CLIENT=localhost/rdp-vscode-e2e-client:dev
POD=rdp-vscode-attached-test
HOMEVOL=rdp-vscode-attached-home
RUNVOL=rdp-vscode-attached-run
PORT=33392
SOCK=/run/rdp-workspace/vscode.sock
OUT=$PWD/test/e2e/out
mkdir -p "$OUT"

cleanup() {
  podman rm -f rdp-vscode-attached-client rdp-vscode-attached-solo >/dev/null 2>&1
  podman pod rm -f "$POD" >/dev/null 2>&1
  podman volume rm -f "$HOMEVOL" "$RUNVOL" >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

wait_for() {  # wait_for <seconds> <bash condition>
  for _ in $(seq "$1"); do eval "$2" && return 0; sleep 1; done
  return 1
}
ax() { podman exec "$POD-attached" bash -c "$1"; }   # in the attached container
dx() { podman exec "$POD-desktop" bash -c "$1"; }    # in the desktop container
# Main codium processes in the attached container (see session.test.sh)
codium_main() { ax 'ps -u bigred -o args= | grep "^/usr/share/codium/codium --user-data-dir=" | grep -v -- "--type=" || true'; }
# What the desktop's button does: send the display, print the reply
ask() {  # ask <account> <display>
  dx "su $1 -s /bin/sh -c 'perl -MIO::Socket::UNIX -e \"\\\$s = IO::Socket::UNIX->new(Peer => \\\"$SOCK\\\") or die; print \\\$s \\\"$2\\\\n\\\"; print scalar <\\\$s>\"'"
}

podman build -q -t "$CLIENT" test/e2e/client >/dev/null || { bad "build e2e client"; finish; }

say invalid-mode
out=$(timeout 20 podman run --rm --name rdp-vscode-attached-solo -e RDP_PASSWORD=x -e RDP_MODE=bogus "$IMG" 2>&1); rc=$?
podman rm -f rdp-vscode-attached-solo >/dev/null 2>&1
[ "$rc" -ne 124 ] || rc=0   # still running after 20s: the mode was not rejected
[ "$rc" -ne 0 ] && grep -q "RDP_MODE" <<<"$out" && pass "an unknown RDP_MODE stops the container with a message" \
  || bad "RDP_MODE=bogus: rc=$rc out=$out"

say waits-for-home
# The desktop container creates the homes. Started alone, an attached container
# must neither create a home nor serve requests until the home is there.
podman volume create "$HOMEVOL" >/dev/null; podman volume create "$RUNVOL" >/dev/null
podman run -d --name rdp-vscode-attached-solo -e RDP_PASSWORD=bigred -e RDP_MODE=attached \
  -v "$HOMEVOL:/home" -v "$RUNVOL:/run/rdp-workspace" "$IMG" >/dev/null
sleep 6
sx() { podman exec rdp-vscode-attached-solo bash -c "$1"; }
sx 'id -u bigred >/dev/null 2>&1' && pass "account exists before its home does" || bad "no bigred account"
sx '[ ! -e /home/bigred ]' && pass "attached mode does not create the home" || bad "attached mode created /home/bigred"
sx "[ ! -S $SOCK ]" && pass "not serving while the home is missing" || bad "socket exists before the home"
# Now the "desktop" creates the home, with a settings file of the user's own
sx 'install -d -m 700 -o bigred -g bigred /home/bigred /home/bigred/.config /home/bigred/.config/VSCodium /home/bigred/.config/VSCodium/User
    echo "{\"mine\": true}" > /home/bigred/.config/VSCodium/User/settings.json
    chown bigred:bigred /home/bigred/.config/VSCodium/User/settings.json'
wait_for 20 "sx '[ -S $SOCK ]'" && pass "serves once the home exists" || bad "no socket 20s after the home appeared"
sx 'grep -q mine /home/bigred/.config/VSCodium/User/settings.json' && pass "existing settings are kept" || bad "settings.json was overwritten"
sx '[ -f /home/bigred/.bashrc ] && [ "$(stat -c %U /home/bigred/.bashrc)" = bigred ]' \
  && pass "missing default files are added, owned by the account" || bad "no bigred-owned ~/.bashrc"
sx '! pgrep -x xrdp >/dev/null && ! pgrep -x xrdp-sesman >/dev/null' && pass "no xrdp, no xrdp-sesman" || bad "xrdp is running in attached mode"
sx '! (exec 3<>/dev/tcp/127.0.0.1/3389) 2>/dev/null' && pass "nothing listens on 3389" || bad "port 3389 is open in attached mode"
podman rm -f rdp-vscode-attached-solo >/dev/null; podman volume rm -f "$HOMEVOL" "$RUNVOL" >/dev/null

say pod
podman volume create "$HOMEVOL" >/dev/null; podman volume create "$RUNVOL" >/dev/null
podman pod create --name "$POD" --shm-size 1g -p "$PORT:3389" >/dev/null
podman run -d --pod "$POD" --name "$POD-desktop" -e RDP_PASSWORD=bigred \
  -v "$HOMEVOL:/home" -v "$RUNVOL:/run/rdp-workspace" "$IMG" >/dev/null
wait_for 20 "nc -z 127.0.0.1 $PORT 2>/dev/null" && pass "desktop (standalone) up" || { bad "desktop did not start"; finish; }
podman run -d --pod "$POD" --name "$POD-attached" -e RDP_PASSWORD=bigred -e RDP_MODE=attached \
  -v "$HOMEVOL:/home" -v "$RUNVOL:/run/rdp-workspace" "$IMG" >/dev/null
wait_for 20 "ax '[ -S $SOCK ]'" && pass "attached container serving" || { bad "attached container not serving"; podman logs "$POD-attached" 2>&1 | tail -5; finish; }
[ "$(dx 'pgrep -xc xrdp')" -ge 1 ] && [ "$(ax 'pgrep -xc xrdp || true')" = 0 ] \
  && pass "one xrdp in the pod (desktop only)" || bad "xrdp count: desktop=$(dx 'pgrep -xc xrdp') attached=$(ax 'pgrep -xc xrdp || true')"

say launch
podman run -d --name rdp-vscode-attached-client --network host -v "$OUT:/out:Z" \
  "$CLIENT" "127.0.0.1:$PORT" bigred bigred attached-1 :95 >/dev/null
wait_for 60 'dx "ls /tmp/.X11-unix/ 2>/dev/null | grep -q ^X"' || bad "no desktop session after login"
disp=":$(dx 'ls /tmp/.X11-unix/ | sed -n "s/^X//p" | head -1')"
[ -z "$(codium_main)" ] && pass "no VSCodium in the attached container before a request" || bad "VSCodium already running: $(codium_main)"
r=$(ask bigred "$disp")
[ "$r" = OK ] && pass "request on $disp accepted" || bad "request on $disp: $r"
if wait_for 40 '[ -n "$(codium_main)" ]'; then
  pass "VSCodium runs in the attached container"
  sleep 10   # an X client without access dies within a second or two
  [ -n "$(codium_main)" ] && pass "and stays on the desktop's display" || bad "VSCodium exited: $(podman logs "$POD-attached" 2>&1 | tail -3)"
  ax '! pgrep -u bigred -x openbox >/dev/null' && pass "no second window manager" || bad "openbox runs in the attached container"
else
  bad "no VSCodium within 40s: $(podman logs "$POD-attached" 2>&1 | tail -3)"
fi

say second-request
# Pressing the button again must not wipe the running VSCodium's data dir
d1=$(codium_main | grep -Eo -- '--user-data-dir[= ][^ ]*' | head -1 | cut -c17-)
r=$(ask bigred "$disp"); sleep 8
[ "$r" = OK ] && pass "second request accepted" || bad "second request: $r"
[ "$(codium_main | grep -c -- "--user-data-dir=$d1 ")" -ge 1 ] && ax "test -d $d1/User/" \
  && pass "the first VSCodium keeps running with its data dir" || bad "after a second request: $(codium_main) / $(ax "ls -la $d1" 2>&1 | head -3)"
n=$(codium_main | grep -Eo -- '--user-data-dir[= ][^ ]*' | sort -u | wc -l)
[ "$n" -eq 1 ] && pass "still one VSCodium instance for this desktop" || bad "distinct instances: $n"

say close
ax 'pkill -u bigred -f /usr/share/codium' || true
wait_for 15 "[ -z \"\$(ax 'ls -d /tmp/sess/*.1000 2>/dev/null')\" ]" && pass "closing VSCodium removes its session dir" || bad "session dir left: $(ax 'ls -d /tmp/sess/*')"
dx 'ls /tmp/.X11-unix/ | grep -q ^X' && pass "the desktop is still there" || bad "closing VSCodium ended the desktop"

finish
