#!/usr/bin/env bash
# rdp-vscode quick start for Kubernetes: one account, bigred / bigred, /home in
# an emptyDir (files are lost when the Pod restarts).
#
#   curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
#
# For several accounts, your own passwords or a persistent /home, use the
# kustomize overlays manifests/stateless or manifests/stateful instead (see README).
#
# Optional, mainly for testing:
#   RDP_VSCODE_REF    branch or tag of github.com/braveantony/rdp-vscode to deploy (default: main)
#   RDP_VSCODE_IMAGE  image to run instead of the one in manifests/base
#   RDP_VSCODE_RAW    where to fetch manifests/ from (default: raw.githubusercontent.com)
#
# Uninstall: kubectl delete namespace rdp-vscode
set -euo pipefail

main() {
  local ref=${RDP_VSCODE_REF:-main}
  local raw=${RDP_VSCODE_RAW:-https://raw.githubusercontent.com/braveantony/rdp-vscode/$ref}
  local ns=rdp-vscode

  need kubectl
  need curl
  kubectl version --request-timeout=10s >/dev/null 2>&1 \
    || die "kubectl cannot reach a cluster; check your kubeconfig/context"

  # Global, not local: the EXIT trap runs after main has returned
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  say "Fetching manifests ($ref)"
  mkdir -p "$tmp/base"
  local f
  for f in kustomization.yaml namespace.yaml deployment.yaml service.yaml; do
    curl -fsSL "$raw/manifests/base/$f" -o "$tmp/base/$f" || die "cannot download manifests/base/$f from $raw"
  done
  curl -fsSL "$raw/manifests/stateless/home-emptydir.yaml" -o "$tmp/home-emptydir.yaml" \
    || die "cannot download manifests/stateless/home-emptydir.yaml from $raw"

  echo "bigred:bigred" > "$tmp/users.txt"
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "namespace: $ns"
    echo "resources:"
    echo "- base"
    echo "patches:"
    echo "- path: home-emptydir.yaml"
    echo "secretGenerator:"
    echo "- name: rdp-vscode-users"
    echo "  files:"
    echo "  - users=users.txt"
    if [ -n "${RDP_VSCODE_IMAGE:-}" ]; then
      # A tag is the part after the last ":" only if it has no "/" (registry ports have one after them)
      local name=$RDP_VSCODE_IMAGE tag=""
      case "${RDP_VSCODE_IMAGE##*:}" in
        */*|"$RDP_VSCODE_IMAGE") ;;
        *) name=${RDP_VSCODE_IMAGE%:*}; tag=${RDP_VSCODE_IMAGE##*:} ;;
      esac
      echo "images:"
      echo "- name: ghcr.io/braveantony/rdp-vscode"
      echo "  newName: $name"
      [ -z "$tag" ] || echo "  newTag: $tag"
    fi
  } > "$tmp/kustomization.yaml"

  say "Applying with kustomize"
  kubectl apply -k "$tmp"
  say "Waiting for the pod (the first image pull is about 1.3 GB)"
  kubectl -n "$ns" rollout status deploy/rdp-vscode --timeout=900s

  # Each account list gets a new hashed Secret name; drop the old ones
  local cur s
  cur=$(kubectl -n "$ns" get deploy rdp-vscode \
    -o jsonpath='{.spec.template.spec.volumes[?(@.name=="users")].secret.secretName}')
  for s in $(kubectl -n "$ns" get secret -o name | grep '^secret/rdp-vscode-users-' || true); do
    [ "$s" = "secret/$cur" ] || kubectl -n "$ns" delete "$s"
  done

  local port ips
  port=$(kubectl -n "$ns" get svc rdp-vscode -o jsonpath='{.spec.ports[0].nodePort}')
  ips=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{end}')

  echo
  say "rdp-vscode is ready"
  echo "  Connect with Windows Remote Desktop (mstsc) to any node:"
  for f in $ips; do echo "    $f:$port"; done
  echo "  On the xrdp login screen keep Session = Xorg and log in as bigred / bigred."
  echo "  VSCodium then asks for the SSH password of tkadm.taroko (bigred)."
  echo "  More accounts, other passwords or a persistent /home: see manifests/ (kustomize) in the repo."
  echo "  Uninstall: kubectl delete namespace $ns"
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }
say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

main "$@"
