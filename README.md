# rdp-vscode

[繁體中文](README.zh-TW.md)

> **Security warning.** The default account `bigred` / `bigred` is for isolated lab clusters only. Anyone who can reach NodePort 30390 with it gets a shell-equivalent inside the cluster network, can SSH to `tkadm`, and through `kubectl` on `tkadm` controls the whole cluster. Change the passwords in `deploy/*/users.txt` before you deploy anywhere else.

Log in with any RDP client (Windows Remote Desktop, Remmina, FreeRDP) and get a full-screen [VSCodium](https://vscodium.com/) running inside your Kubernetes cluster. On login it connects over SSH to the cluster's admin Pod (`tkadm` by default) with [Open Remote-SSH](https://open-vsx.org/extension/jeanp413/open-remote-ssh), so you edit files and run `kubectl` there. Because the editor itself runs in the cluster, you can open your Services by their DNS names, such as `http://web.default.svc.cluster.local`, without port-forwarding or Ingress.

```text
RDP client ──> NodePort 30390 ──> rdp-vscode Pod
                                  ├─ xrdp: one Xorg per RDP connection
                                  └─ VSCodium (full screen, openbox) ──SSH 22100──> tkadm Pod (kubectl)
                                        └─ Integrated Browser ──> http://<svc>.<ns>.svc.<cluster-domain>
```

## Quick start

Requirements:

- A Kubernetes cluster you can `kubectl apply` to.
- An SSH target that VSCodium can reach. The defaults point to `tkadm.taroko:22100`, user `bigred`. Its sshd must allow local port forwarding (`AllowTcpForwarding local` or `yes`); Open Remote-SSH tunnels to its server through it. Alpine's openssh ships with `AllowTcpForwarding no`.

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
kubectl apply -k deploy/stateless
kubectl -n rdp-vscode rollout status deploy/rdp-vscode
kubectl get nodes -o wide        # any node's INTERNAL-IP
```

Connect your RDP client to `<node IP>:30390`. On the xrdp login screen keep Session `Xorg` and log in with `bigred` / `bigred`. VSCodium asks for the SSH password of `tkadm` (`bigred`). See the [user guide](user-guide.md) (Traditional Chinese).

## Stateless or stateful

| Overlay | `/home` | When the Pod restarts |
|---|---|---|
| `deploy/stateless` | `emptyDir` | Files, settings and user-installed extensions are lost |
| `deploy/stateful` | PVC `rdp-vscode-home`, 5Gi, ReadWriteOnce | Everything under `/home` is kept |

The stateful PVC has no `storageClassName`, so it uses the cluster's default StorageClass. That class must bind on first use (`volumeBindingMode: WaitForFirstConsumer`, as `local-path` should) or be network storage. With `Immediate`, a node-local provisioner such as `local-path` cannot tell which node to create the volume on, and the PVC stays `Pending` with `no node was specified`. A `local-path` volume also lives on one node: if that node is down, the Pod cannot start.

`deploy/example/ssh-configmap` shows how to replace the generated SSH config with your own file.

## Accounts

`deploy/*/users.txt` holds one `user:password` per line (Windows line endings are fine) and becomes the Secret `rdp-vscode-users`. Accounts get UIDs 1000, 1001, … in file order and private homes (`0700`). If you reorder the file on a stateful deployment, existing homes are handed to the new UIDs at startup; the home of an account you remove is locked to root, so whoever gets its old UID cannot read it. All accounts share the same SSH login on `tkadm`.

Several people, or the same account twice, can be logged in at once (`MAX_SESSIONS`). Each RDP connection gets its own desktop and its own VSCodium; settings in `~/.config/VSCodium/User` are shared between sessions of one account. A disconnected session cannot be resumed and is removed 120 seconds later. Closing VSCodium ends the session.

## Configuration

Set these on the Deployment (`deploy/base/deployment.yaml`).

| Variable | Default | Meaning |
|---|---|---|
| `MAX_SESSIONS` | `3` | Concurrent RDP sessions, all accounts together |
| `SSH_HOST_ALIAS` | `tkadm` | SSH `Host` name VSCodium connects to on login; empty disables the auto connect |
| `SSH_HOST` | `tkadm.taroko` | Host name or IP of the SSH target |
| `SSH_PORT` | `22100` | SSH port |
| `SSH_USER` | `bigred` | SSH user |
| `SSH_REMOTE_FOLDER` | `/home/bigred` | Folder opened on the SSH target |
| `VSCODIUM_LOCALE` | `zh-tw` | UI language: `zh-tw` or `en` |

The generated config is written to `/etc/ssh/ssh_config.d/rdp-vscode.conf`. A non-empty ConfigMap `rdp-vscode-ssh` (key `config`) replaces it entirely.

**Cluster DNS names.** `SSH_HOST` uses the short name `tkadm.taroko` (`<service>.<namespace>`), which works with any cluster domain. For websites you can use the short name or the full `<svc>.<ns>.svc.<cluster-domain>`. The cluster domain is not always `cluster.local` (on tk8s it is `tk8s.k8s`); look it up with:

```bash
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep kubernetes
```

## Resources

Requests `500m` CPU and `1Gi` memory; limits `4` CPU and `4Gi`, sized for 3 sessions. Each extra session needs about 1Gi more. If the Pod hits its memory limit it is OOM-killed and every session ends. `/dev/shm` is a 1Gi in-memory `emptyDir`: with the 64MiB default, VSCodium crashes while loading the CJK fonts.

## Images

| Tag | Contents | Size |
|---|---|---|
| `ghcr.io/braveantony/rdp-vscode:1.0` | VSCodium 1.143.17183, Open Remote-SSH 0.5.1, Traditional Chinese language pack 1.131.0 | about 1.3GB |
| `ghcr.io/braveantony/rdp-vscode:1.0-firefox` | The above plus Firefox ESR as the default browser | about 1.6GB |

Build them yourself with [build-image.md](build-image.md) (Traditional Chinese).

## Known limitations

- All RDP accounts log in to `tkadm` as the same user, so they share its files and its `kubectl` permissions.
- `~/.vscodium-server` on `tkadm` is not persistent: after `tkadm` restarts, the first connection downloads the server again (about 90MB).
- Only extensions from [Open VSX](https://open-vsx.org/) are available; Microsoft-only extensions such as Pylance, C# Dev Kit and Copilot are not.
- Open Remote-SSH asks for the SSH password again on every reconnect, including `Reload Window`.
- Links are not opened in the built-in browser automatically; open the Integrated Browser yourself (`Browser: Open Integrated Browser`).
- You cannot type Chinese inside the Pod; type it on your own computer and paste it.
- The xrdp listener runs as root: Debian trixie's xrdp 0.10.1 cannot drop privileges.

## License

[Apache-2.0](LICENSE)
