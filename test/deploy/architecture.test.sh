#!/usr/bin/env bash
# Checks a running deployment against docs/architecture/rdp-vscode-architecture.png.
# Read-only: it only runs kubectl get/logs and read-only commands inside the pods.
#   bash test/deploy/architecture.test.sh
# Sections follow docs/verify-architecture.md. Checks that need someone logged in
# over RDP (and connected to tkadm) are skipped when nobody is.
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
NS=${NS:-rdp-vscode}
TKADM_NS=${TKADM_NS:-taroko}
_skips=0
skip() { _skips=$((_skips + 1)); printf 'SKIP %s\n' "$*"; }

# jsonpath on the Deployment / Service
dep() { kubectl -n "$NS" get deploy rdp-vscode -o jsonpath="$1" 2>/dev/null; }
svc() { kubectl -n "$NS" get svc rdp-vscode -o jsonpath="$1" 2>/dev/null; }
# Read-only shell command in the rdp-vscode pod / tkadm
px() { kubectl -n "$NS" exec deploy/rdp-vscode -c desktop -- bash -c "$1" 2>/dev/null; }
tx() { kubectl -n "$TKADM_NS" exec deploy/tkadm -c tkadm -- sh -c "$1" 2>/dev/null; }
is() { [ "$2" = "$3" ] && pass "$1" || bad "$1: want '$3' got '$2'"; }
# Container env as the pod sees it; the second argument is the image default
env_of() {
  local v
  v=$(dep "{.spec.template.spec.containers[0].env[?(@.name==\"$1\")].value}")
  if [ -n "$(dep "{.spec.template.spec.containers[0].env[?(@.name==\"$1\")].name}")" ]; then echo "$v"; else echo "$2"; fi
}

say "1. RDP entry: node port 30390 -> Service rdp-vscode -> pod port 3389"
kubectl get ns "$NS" >/dev/null 2>&1 || { bad "namespace $NS not found (install first)"; finish; }
is "Service type" "$(svc '{.spec.type}')" NodePort
is "nodePort" "$(svc '{.spec.ports[0].nodePort}')" 30390
target=$(svc '{.spec.ports[0].targetPort}')
cport=$(dep "{.spec.template.spec.containers[0].ports[?(@.name==\"$target\")].containerPort}")
[ -n "$cport" ] || cport=$target
is "Service targetPort $target -> container port" "$cport" 3389
ep=$(kubectl -n "$NS" get endpointslice -l kubernetes.io/service-name=rdp-vscode \
  -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null)
pod_ip=$(kubectl -n "$NS" get pod -l app=rdp-vscode -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[ -n "$pod_ip" ] && [ "$ep" = "$pod_ip" ] && pass "Service forwards to the pod ($pod_ip)" || bad "endpoints '$ep' vs pod IP '$pod_ip'"

say "2. Pod: one container desktop"
is "replicas" "$(dep '{.spec.replicas}')" 1
is "containers" "$(dep '{.spec.template.spec.containers[*].name}')" desktop
is "image" "$(dep '{.spec.template.spec.containers[0].image}')" "ghcr.io/braveantony/rdp-vscode:$(cat VERSION)"

say "3. Account and settings (gold): Secret, optional ConfigMap"
mnt() { dep "{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"$1\")].$2}"; }
vol() { dep "{.spec.template.spec.volumes[?(@.name==\"$1\")].$2}"; }
case $(vol users secret.secretName) in
  rdp-vscode-users-*) pass "Secret $(vol users secret.secretName)" ;;
  *) bad "users volume is not a rdp-vscode-users-<hash> Secret: '$(vol users secret.secretName)'" ;;
esac
is "Secret mounted at" "$(mnt users mountPath)" /etc/rdp-vscode/users
is "Secret read-only" "$(mnt users readOnly)" true
accounts=$(kubectl -n "$NS" logs deploy/rdp-vscode 2>/dev/null | sed -n 's/^\[entrypoint\] accounts: //p' | tail -1)
[ -n "$accounts" ] && pass "accounts created from the Secret: $accounts" || bad "no '[entrypoint] accounts:' line in the pod log"
is "ConfigMap name" "$(vol ssh-config configMap.name)" rdp-vscode-ssh
is "ConfigMap optional" "$(vol ssh-config configMap.optional)" true
is "ConfigMap mounted at" "$(mnt ssh-config mountPath)" /etc/rdp-vscode/ssh
# SSH target: from the SSH_* env, unless a non-empty ConfigMap replaces the config
alias=$(env_of SSH_HOST_ALIAS tkadm)
ssh_alias=${alias:-tkadm}
resolved=$(px "ssh -G '$ssh_alias'")
ssh_host=$(sed -n 's/^hostname //p' <<<"$resolved")
ssh_port=$(sed -n 's/^port //p' <<<"$resolved")
conf=$(px 'cat /etc/ssh/ssh_config.d/rdp-vscode.conf')
if px 'test -s /etc/rdp-vscode/ssh/config'; then
  grep -qx "Host $ssh_alias" <<<"$conf" && pass "ssh config from ConfigMap has Host $ssh_alias ($ssh_host:$ssh_port)" \
    || bad "ConfigMap ssh config has no 'Host $ssh_alias'"
else
  want_host=$(env_of SSH_HOST tkadm.taroko); want_port=$(env_of SSH_PORT 22100)
  [ "$ssh_host:$ssh_port" = "$want_host:$want_port" ] && grep -qx "Host $ssh_alias" <<<"$conf" \
    && pass "ssh config: Host $ssh_alias -> $ssh_host:$ssh_port" \
    || bad "ssh config: want Host $ssh_alias -> $want_host:$want_port, got $ssh_host:$ssh_port in: $conf"
fi

say "4. Volumes: /home and /dev/shm"
if [ "$(vol home persistentVolumeClaim.claimName)" = rdp-vscode-home ]; then pass "/home is PVC rdp-vscode-home (stateful)"
elif [ -n "$(vol home emptyDir)" ]; then pass "/home is emptyDir (stateless)"
else bad "/home is neither emptyDir nor PVC rdp-vscode-home"; fi
is "/home mounted at" "$(mnt home mountPath)" /home
is "/dev/shm medium" "$(vol dshm emptyDir.medium)" Memory
is "/dev/shm sizeLimit" "$(vol dshm emptyDir.sizeLimit)" 1Gi
is "/dev/shm mounted at" "$(mnt dshm mountPath)" /dev/shm
is "/dev/shm size in the pod" "$(px 'df -h --output=size /dev/shm | tail -1 | tr -d " "')" 1.0G

say "5. (1) xrdp :3389 / xrdp-sesman, started by tini + entrypoint.sh"
is "PID 1" "$(px 'cat /proc/1/comm')" tini
ep_pid=$(px 'ps -eo pid=,ppid=,args= | awk "\$2 == 1 && \$3 == \"bash\" && \$4 == \"/opt/rdp-vscode/entrypoint.sh\" {print \$1}"')
[ -n "$ep_pid" ] && pass "tini runs entrypoint.sh (pid $ep_pid)" || bad "entrypoint.sh is not a child of tini"
for p in xrdp xrdp-sesman; do
  is "$p runs as" "$(px "ps -o user= -C $p | head -1")" root
  is "$p parent is entrypoint.sh" "$(px "ps -o ppid= -C $p | head -1 | tr -d ' '")" "$ep_pid"
done
# 0D3D = 3389, state 0A = LISTEN
px 'cat /proc/net/tcp /proc/net/tcp6 | awk "\$2 ~ /:0D3D\$/ && \$4 == \"0A\"" | grep -q .' \
  && pass "listening on 3389" || bad "nothing listens on 3389"

say "6. (2) Xorg session x N with openbox and full-screen VSCodium"
ors=$(sed -n 's/^ARG OPEN_REMOTE_SSH_VERSION=//p' images/rdp-vscode/Dockerfile)
zh=$(sed -n 's/^ARG ZH_HANT_VERSION=//p' images/rdp-vscode/Dockerfile)
vsix=$(px 'ls /opt/rdp-vscode/vsix')
for f in "jeanp413.open-remote-ssh-$ors.vsix" "ms-ceintl.vscode-language-pack-zh-hant-$zh.vsix"; do
  grep -qx "$f" <<<"$vsix" && pass "pre-installed $f" || bad "missing /opt/rdp-vscode/vsix/$f"
done
# One desktop per running Xorg: "<display>.<uid>", the name of its /tmp/sess dir
sessions=$(px 'ps -C Xorg -o uid=,args= | sed -n "s/^ *\([0-9]*\) .* :\([0-9]*\)\( .*\)\{0,1\}$/\2.\1/p"')
if [ -z "$sessions" ]; then
  skip "nobody is logged in over RDP; log in and run again to check (2) and (3)"
  stale=$(px 'ls /tmp/sess 2>/dev/null' | tr '\n' ' ')
  [ -z "$stale" ] || printf 'NOTE /tmp/sess has leftover dirs without an Xorg: %s\n' "$stale"
else
  for s in $sessions; do
    uid=${s#*.}; user=$(px "getent passwd $uid | cut -d: -f1")
    px "test -d /tmp/sess/$s" && pass "session $s ($user): /tmp/sess/$s" || bad "session $s: no /tmp/sess/$s"
    px "ps -u $uid -o comm= | grep -qx openbox" && pass "session $s ($user): openbox" || bad "session $s: no openbox"
    args=$(px "ps -u $uid -o args= | grep '^/usr/share/codium/codium ' | grep -v -- --type= | grep -- '--user-data-dir=/tmp/sess/$s/'")
    [ -n "$args" ] && pass "session $s: VSCodium" || bad "session $s: no VSCodium"
    if [ -n "$alias" ]; then
      grep -q -- "--remote=ssh-remote+$alias" <<<"$args" && pass "session $s: VSCodium auto-connects to $alias" \
        || bad "session $s: no --remote=ssh-remote+$alias in: $args"
    fi
  done
fi

say "7. Green: SSH to $ssh_host:$ssh_port, sshd forwarding, (3) vscodium-server"
is "tkadm Service port" "$(kubectl -n "$TKADM_NS" get svc tkadm -o jsonpath="{.spec.ports[?(@.port==$ssh_port)].port}" 2>/dev/null)" "$ssh_port"
banner=$(px "timeout 5 bash -c 'exec 3<>/dev/tcp/$ssh_host/$ssh_port; head -c 7 <&3'")
is "pod reaches $ssh_host:$ssh_port (SSH banner)" "$banner" SSH-2.0
fwd=$(tx '/usr/sbin/sshd -T 2>/dev/null | sed -n "s/^allowtcpforwarding //p"')
case $fwd in local | yes) pass "tkadm sshd AllowTcpForwarding $fwd" ;; *) bad "tkadm sshd AllowTcpForwarding '$fwd' (want local or yes)" ;; esac
# An established TCP connection (state 01) from the pod to the SSH port means a
# desktop is connected right now; a vscodium-server left over from an earlier
# connection keeps running for a while after it ends, so its process alone proves nothing.
port_hex=$(printf '%04X' "$ssh_port")
connected=$(px "cat /proc/net/tcp /proc/net/tcp6 | awk '\$3 ~ /:$port_hex\$/ && \$4 == \"01\"' | grep -c .")
if [ "${connected:-0}" -eq 0 ]; then
  skip "(3) vscodium-server: no desktop is connected to $ssh_host:$ssh_port right now (log in and enter the SSH password, then run again)"
elif tx 'ps -eo args= | grep -q "[.]vscodium-server/bin/.*/node"'; then
  pass "(3) $connected SSH connection(s) to $ssh_host:$ssh_port; vscodium-server is running on tkadm"
  px 'ps -eo args= | grep -q "[.]vscodium-server"' && bad "vscodium-server also found in the rdp-vscode pod" || pass "no vscodium-server in the rdp-vscode pod"
else
  bad "(3) connected to $ssh_host:$ssh_port but no vscodium-server on tkadm"
fi

say "8. Orange: Integrated Browser reaches cluster Services, kubectl on tkadm"
px 'getent hosts kubernetes.default >/dev/null' && pass "pod resolves <service>.<namespace> (kubernetes.default)" \
  || bad "pod cannot resolve kubernetes.default"
px 'timeout 5 bash -c "exec 3<>/dev/tcp/kubernetes.default/443"' && pass "pod connects to a cluster Service (kubernetes.default:443)" \
  || bad "pod cannot connect to kubernetes.default:443"
ver=$(tx 'kubectl version 2>/dev/null | sed -n "s/^Server Version: //p"')
[ -n "$ver" ] && pass "kubectl on tkadm reaches the Kubernetes API ($ver)" || bad "kubectl on tkadm cannot reach the API"

printf '\n%d skipped\n' "$_skips"
finish
