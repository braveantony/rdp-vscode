#!/usr/bin/env bash
# Render every kustomize overlay and check it: bash tests/deploy/render.test.sh
# Needs kubectl (with a reachable cluster for the server-side dry run) and PyYAML.
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# check <overlay> <python expression over docs>: docs is the list of rendered objects
check() {
  python3 -c '
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
kind = lambda k: [d for d in docs if d["kind"] == k]
dep = (kind("Deployment") or [{}])[0]
pod = dep.get("spec", {}).get("template", {}).get("spec", {})
ctr = (pod.get("containers") or [{}])[0]
mounts = {m["mountPath"]: m for m in ctr.get("volumeMounts", [])}
vols = {v["name"]: v for v in pod.get("volumes", [])}
vol_at = lambda p: vols.get(mounts.get(p, {}).get("name"), {})
env = {e["name"]: e.get("value") for e in ctr.get("env", [])}
sys.exit(0 if eval(sys.argv[2]) else 1)
' "$TMP/$1.yaml" "$2"
}
expect() {  # expect <overlay> <description> <python expression>
  check "$1" "$3" && pass "$1: $2" || bad "$1: $2"
}

for o in stateless stateful example/ssh-configmap; do
  name=${o//\//-}
  if kubectl kustomize "deploy/$o" > "$TMP/$name.yaml" 2>"$TMP/$name.err"; then
    pass "$o renders"
  else
    bad "$o does not render: $(head -3 "$TMP/$name.err")"; continue
  fi
  expect "$name" "all namespaced objects in rdp-vscode" \
    'all(d["metadata"].get("namespace") == "rdp-vscode" for d in docs if d["kind"] != "Namespace") and kind("Namespace")[0]["metadata"]["name"] == "rdp-vscode"'
  expect "$name" "NodePort 30390" 'kind("Service")[0]["spec"]["ports"][0]["nodePort"] == 30390'
  expect "$name" "limits 4 / 4Gi" 'ctr["resources"]["limits"] == {"cpu": "4", "memory": "4Gi"}'
  expect "$name" "requests 500m / 1Gi" 'ctr["resources"]["requests"] == {"cpu": "500m", "memory": "1Gi"}'
  expect "$name" "/dev/shm is a 1Gi Memory emptyDir" 'vol_at("/dev/shm").get("emptyDir") == {"medium": "Memory", "sizeLimit": "1Gi"}'
  expect "$name" "users Secret at /etc/rdp-vscode/users" \
    'vol_at("/etc/rdp-vscode/users")["secret"]["secretName"].startswith("rdp-vscode-users") and mounts["/etc/rdp-vscode/users"]["subPath"] == "users" and any(s["metadata"]["name"].startswith("rdp-vscode-users") and "users" in s["data"] for s in kind("Secret"))'
  expect "$name" "optional ssh ConfigMap at /etc/rdp-vscode/ssh" \
    'vol_at("/etc/rdp-vscode/ssh")["configMap"]["name"].startswith("rdp-vscode-ssh") and vol_at("/etc/rdp-vscode/ssh")["configMap"]["optional"] is True'
  expect "$name" "env defaults" \
    'env == {"MAX_SESSIONS": "3", "SSH_HOST_ALIAS": "tkadm", "SSH_HOST": "tkadm.taroko", "SSH_PORT": "22100", "SSH_USER": "bigred", "SSH_REMOTE_FOLDER": "/home/bigred", "VSCODIUM_LOCALE": "zh-tw"}'
  expect "$name" "strategy Recreate" 'dep["spec"]["strategy"]["type"] == "Recreate"'
done

expect stateless "/home is an emptyDir" '"emptyDir" in vol_at("/home")'
expect stateless "no PVC" 'not kind("PersistentVolumeClaim")'
expect stateful "/home is PVC rdp-vscode-home" 'vol_at("/home")["persistentVolumeClaim"]["claimName"] == "rdp-vscode-home"'
expect stateful "PVC 5Gi RWO without storageClassName" \
  'kind("PersistentVolumeClaim")[0]["spec"]["resources"]["requests"]["storage"] == "5Gi" and kind("PersistentVolumeClaim")[0]["spec"]["accessModes"] == ["ReadWriteOnce"] and "storageClassName" not in kind("PersistentVolumeClaim")[0]["spec"]'
expect example-ssh-configmap "ConfigMap rdp-vscode-ssh with key config" \
  'any(c["metadata"]["name"].startswith("rdp-vscode-ssh") and "config" in c["data"] for c in kind("ConfigMap"))'
expect example-ssh-configmap "/home is an emptyDir (built on stateless)" '"emptyDir" in vol_at("/home")'
for o in stateless stateful; do
  grep -q '^# .*password' "deploy/$o/users.txt" 2>/dev/null && pass "$o users.txt warns to change the password" || bad "$o users.txt has no password warning"
done

say server-dry-run
# The rdp-vscode namespace may not exist yet, and a dry run never creates it,
# so validate the objects in the existing "default" namespace instead.
for o in stateless stateful example-ssh-configmap; do
  python3 -c '
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d and d["kind"] != "Namespace"]
for d in docs: d["metadata"]["namespace"] = "default"
yaml.safe_dump_all(docs, sys.stdout)
' "$TMP/$o.yaml" > "$TMP/$o.default.yaml"
  out=$(kubectl apply --dry-run=server -f "$TMP/$o.default.yaml" 2>&1) && pass "dry-run $o" || bad "dry-run $o: $(tail -2 <<<"$out")"
done

finish
