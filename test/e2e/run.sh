#!/usr/bin/env bash
# End-to-end acceptance on the tk8s cluster: bash test/e2e/run.sh [stateless|stateful|all]
# Builds the image, loads it into the worker nodes, deploys (stateless: install.sh
# from this checkout; stateful: kustomize), logs in over RDP with the e2e client
# and checks AC1-AC10.
# E2E_KEEP=1 keeps the rdp-vscode namespace afterwards.
# shellcheck disable=SC1091,SC2015,SC2016  # pass() never fails; single-quoted scripts run elsewhere
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
MODE=${1:-all}
IMG=localhost/rdp-vscode:dev
CLIENT=localhost/rdp-vscode-e2e-client:dev
NS=rdp-vscode
PORT=33390
OUT=$PWD/test/e2e/out
WORK=$(mktemp -d)
NODES="tk8s-worker-1 tk8s-worker-2"
MARKER=/tmp/rdp-vscode-e2e.marker
pf_pid=""
mkdir -p "$OUT"

tk() { kubectl -n taroko exec deploy/tkadm -c tkadm -- "$@"; }
px() { kubectl -n "$NS" exec deploy/rdp-vscode -- bash -c "$1"; }
codium_main() { px 'ps -u bigred -o args= | grep "^/usr/share/codium/codium " | grep -v -- "--type=" || true'; }
xorg_count() { px 'ps -u bigred -o comm= | grep -c "^Xorg" || true'; }
wait_for() {  # wait_for <seconds> <bash condition>
  for _ in $(seq "$1"); do eval "$2" && return 0; sleep 1; done
  return 1
}

clients_rm() { podman rm -f rdp-vscode-e2e-client >/dev/null 2>&1; }
pf_stop() { [ -n "$pf_pid" ] && kill "$pf_pid" 2>/dev/null; pf_pid=""; }
pf_start() {
  pf_stop
  kubectl -n "$NS" port-forward svc/rdp-vscode "$PORT:3389" >"$WORK/pf.log" 2>&1 &
  pf_pid=$!
  wait_for 20 'nc -z 127.0.0.1 $PORT 2>/dev/null'
}
login() {  # login <screenshot name>: one RDP client logged in as bigred
  clients_rm
  podman run -d --name rdp-vscode-e2e-client --network host -v "$OUT:/out:Z" \
    "$CLIENT" "127.0.0.1:$PORT" bigred bigred "$1" :95 >/dev/null
}
rollout() {  # rollout: wait for the new pod, then reconnect the port-forward
  kubectl -n "$NS" rollout status deploy/rdp-vscode --timeout=300s >/dev/null &&
    kubectl -n "$NS" wait --for=condition=Ready pod -l app=rdp-vscode --timeout=180s >/dev/null &&
    pf_start
}

cleanup() {
  clients_rm
  pf_stop
  tk sh -c "kubectl delete deploy/web svc/web -n default --ignore-not-found >/dev/null; rm -f $MARKER" 2>/dev/null
  [ "${E2E_KEEP:-0}" = 1 ] || kubectl delete ns "$NS" --ignore-not-found --wait=true >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

say build
podman build -q -t "$IMG" images/rdp-vscode >/dev/null && pass "image built" || { bad "image build"; finish; }
podman build -q -t "$CLIENT" test/e2e/client >/dev/null || { bad "client build"; finish; }
podman save -o "$WORK/img.tar" "$IMG" >/dev/null
for n in $NODES; do
  sudo podman --root "/var/lib/containers/storage/volumes/$n-var/_data/lib/containers/storage" \
    --runroot "/run/rdp-vscode-load-$n" --storage-driver overlay load -i "$WORK/img.tar" >/dev/null 2>&1 \
    && pass "image loaded into $n" || bad "image load into $n"
done
rm -f "$WORK/img.tar"

deploy() {  # deploy <overlay>: stateless goes through the quick start
  # (install.sh from this checkout), stateful through kustomize. kustomize only
  # accepts relative paths, so its wrapper lives in the git-ignored test/e2e/out/
  if [ "$1" = stateless ]; then
    RDP_VSCODE_RAW="file://$PWD" RDP_VSCODE_IMAGE="$IMG" bash install.sh >"$WORK/install.log" 2>&1 \
      || { tail -5 "$WORK/install.log" >&2; return 1; }
    return 0
  fi
  local k=$OUT/kustomize
  mkdir -p "$k"
  cat > "$k/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../../../manifests/$1
images:
- name: ghcr.io/braveantony/rdp-vscode
  newName: localhost/rdp-vscode
  newTag: dev
EOF
  kubectl apply -k "$k" >/dev/null
}

run_overlay() {  # run_overlay <stateless|stateful>
  local o=$1
  say "$o: deploy"
  kubectl delete ns "$NS" --ignore-not-found --wait=true >/dev/null 2>&1
  deploy "$o" || { bad "$o: apply"; return; }
  kubectl -n "$NS" rollout status deploy/rdp-vscode --timeout=300s >/dev/null
  kubectl -n "$NS" wait --for=condition=Ready pod -l app=rdp-vscode --timeout=180s >/dev/null \
    && pass "AC1 $o: pod Ready" || { bad "AC1 $o: pod not Ready"; return; }
  pf_start || { bad "$o: port-forward"; return; }

  say "$o: login (AC2, AC3)"
  tk touch "$MARKER"
  login "$o-1"
  wait_for 60 '[ "$(xorg_count)" -ge 1 ]' && pass "AC2 $o: bigred Xorg" || bad "AC2 $o: no Xorg"
  if wait_for 60 '[ -n "$(codium_main)" ]'; then
    codium_main | grep -q 'ssh-remote+tkadm' && pass "AC3 $o: codium connects to ssh-remote+tkadm" \
      || bad "AC3 $o: no ssh-remote+tkadm in: $(codium_main)"
  else
    bad "AC3 $o: no codium within 60s"
  fi
  sleep 15  # let the password prompt appear
  podman exec rdp-vscode-e2e-client bash -c 'export DISPLAY=:95; xdotool type --delay 60 bigred; xdotool key Return'
  wait_for 90 '[ -n "$(tk find /home/bigred/.vscodium-server -newer $MARKER 2>/dev/null | head -1)" ]' \
    && pass "AC3 $o: vscodium-server updated on tkadm after the password" \
    || bad "AC3 $o: nothing newer than the marker in ~/.vscodium-server"

  say "$o: AC6"
  wait_for 90 'tk sh -c "ls /home/bigred/.vscodium-server/extensions" 2>/dev/null | grep -q "^redhat.vscode-yaml-"' \
    && pass "AC6 $o: redhat.vscode-yaml on tkadm" || bad "AC6 $o: redhat.vscode-yaml not installed on tkadm"
  sleep 5
  podman exec rdp-vscode-e2e-client bash -c 'xwd -display :95 -root -silent | magick xwd:- /out/'"$o"'-connected.png' 2>/dev/null

  say "$o: AC4, AC5"
  tk sh -c 'kubectl -n default create deploy web --image=nginx >/dev/null && kubectl -n default expose deploy web --port 80 >/dev/null && kubectl -n default rollout status deploy/web --timeout=180s >/dev/null' \
    && pass "AC4 $o: kubectl on tkadm deploys web" || bad "AC4 $o: kubectl on tkadm failed"
  wait_for 30 'px "curl -fsS http://web.default.svc.tk8s.k8s" 2>/dev/null | grep -q "Welcome to nginx"' \
    && pass "AC5 $o: web.default.svc.tk8s.k8s reachable from the pod" || bad "AC5 $o: FQDN not reachable"
  tk kubectl -n default delete deploy/web svc/web --ignore-not-found >/dev/null

  if [ "$o" = stateful ]; then
    say "stateful: AC8"
    px "su bigred -c 'sed -i \"1a \\\"editor.fontSize\\\": 17,\" ~/.config/VSCodium/User/settings.json'"
    clients_rm
    kubectl -n "$NS" delete pod -l app=rdp-vscode --wait=true >/dev/null
    rollout || bad "AC8: new pod not Ready"
    login stateful-2
    if wait_for 60 '[ -n "$(codium_main)" ]'; then
      d=$(codium_main | grep -Eo -- '--user-data-dir[= ][^ ]*' | head -1 | cut -c17-)
      px "grep -q '\"editor.fontSize\": 17' $d/User/settings.json" \
        && pass "AC8: setting kept across pod restart ($d)" || bad "AC8: editor.fontSize 17 not in $d/User/settings.json"
    else
      bad "AC8: no codium after re-login"
    fi
  fi

  say "$o: AC7"
  px 'pkill -u bigred -f /usr/share/codium' || true
  wait_for 15 '[ "$(xorg_count)" -eq 0 ] && [ -z "$(px "ls -d /tmp/sess/*.1000 2>/dev/null")" ]' \
    && pass "AC7 $o: closing VSCodium logs out" || bad "AC7 $o: session still there"
  clients_rm

  if [ "$o" = stateless ]; then
    say "stateless: AC10"
    kubectl -n "$NS" set env deploy/rdp-vscode VSCODIUM_LOCALE=en >/dev/null
    rollout || bad "AC10: pod not Ready"
    login stateless-en
    wait_for 60 'codium_main | grep -Eq -- "--locale[= ]en( |$)"' \
      && pass "AC10: --locale en" || bad "AC10: no --locale en in: $(codium_main)"
    clients_rm

    say "stateless: Review Focus 5"
    kubectl -n "$NS" set env deploy/rdp-vscode VSCODIUM_LOCALE=zh-tw SSH_HOST=nonexistent.invalid >/dev/null
    rollout || bad "RF5: pod not Ready"
    login stateless-badhost
    wait_for 60 '[ "$(xorg_count)" -ge 1 ]' || true
    sleep 60
    [ "$(xorg_count)" -ge 1 ] && pass "RF5: unreachable SSH host does not log the user out" \
      || bad "RF5: session ended with an unreachable SSH host"
    clients_rm
  fi
}

case $MODE in
  stateless | stateful) run_overlay "$MODE" ;;
  all) run_overlay stateless; run_overlay stateful ;;
  *) echo "usage: run.sh [stateless|stateful|all]" >&2; exit 2 ;;
esac

finish
