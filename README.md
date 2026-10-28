# rdp-vscode

[繁體中文](README.zh-TW.md)

Log in with Windows Remote Desktop (RDP) and you get a full-screen VSCodium running inside your Kubernetes cluster. It connects over SSH to the cluster's admin Pod (tkadm) on its own, so you edit files and run `kubectl` there. Several people can use it at once, and every login gets its own desktop.

> **Security warning.** The default account `bigred` / `bigred` is for isolated lab clusters only. Anyone who can reach NodePort 30390 with it gets into the cluster network, can SSH to tkadm, and through `kubectl` there controls the whole cluster. Before you deploy anywhere else, switch to [several accounts](#advanced-several-accounts-and-a-persistent-home-kustomize) with your own passwords.

## Overview

- **Code and run the cluster from inside it**: the VSCodium you log in to runs in the cluster
  - **Editor and CLI**: connects to tkadm over SSH (Open Remote-SSH); the explorer and the terminal are on tkadm, and the kubeconfig never leaves the cluster
  - **Web**: open `http://<service>.<namespace>` (for example `http://web.default`) in the built-in Integrated Browser to reach web services inside the cluster
  - Only one NodePort (30390) is exposed; no port-forward, Ingress or extra exposure of your services
- **Nothing to install**: the Remote Desktop client built into Windows is enough; no local VS Code or plugins
- **Concurrent and isolated**: several accounts, or the same account several times, can be logged in at once; every login has its own desktop and VSCodium, and homes are `0700`
- **Chinese UI and YAML completion**: the Traditional Chinese language pack is preinstalled; the YAML extension is installed on tkadm on first connect, so Kubernetes YAML gets field completion
- **Persistent settings** (stateful mode): `/home` lives on a PVC and survives Pod restarts

## Architecture

![rdp-vscode architecture](docs/architecture/rdp-vscode-architecture.png)

The client connects over RDP to NodePort `30390` on any node (a fixed port Kubernetes opens on every node); Service `rdp-vscode` forwards it to port 3389 of the Pod. The Pod has a single container with these processes and sessions:

- ① xrdp / xrdp-sesman: accept RDP connections, show the login screen, check the account, and open a new desktop for every login
- ② Xorg session: one desktop per login, running VSCodium full screen; closing VSCodium logs you out
- VSCodium connects over SSH to tkadm in namespace `taroko` (`tkadm.taroko:22100`) and starts ③ vscodium-server there, so files and terminals are on tkadm

Details in [docs/architecture.md](docs/architecture.md) (Traditional Chinese).

## Prerequisites

### Kubernetes cluster

- kubectl (with its built-in Kustomize, used by `kubectl apply -k`), curl, bash
- A kubeconfig (usually `~/.kube/config`) allowed to create Namespaces, Deployments, Services and Secrets
- Nodes that can pull from `ghcr.io` (the image is about 1.3 GB)
- Resources: the Pod requests 0.5 CPU / 1 GiB and is limited to 4 CPU / 4 GiB (sized for 3 concurrent users)
- NodePort `30390` free, and clients able to reach TCP 30390 on the nodes
- **SSH target**: by default the cluster admin Pod tkadm in namespace `taroko` (`tkadm.taroko:22100`, with kubectl and a kubeconfig). tkadm is deployed separately; this repo does not provide it. Its sshd must allow local port forwarding (`AllowTcpForwarding local` or `yes`) for Open Remote-SSH to work; Alpine's openssh defaults to `no` (how we changed it: [docs/ops/2026-10-27-tkadm-sshd-forwarding.md](docs/ops/2026-10-27-tkadm-sshd-forwarding.md)). Use the `SSH_*` [environment variables](#environment-variables) for another host

### Remote Desktop client

- **Windows**: the built-in Remote Desktop Connection (`mstsc`)
- **macOS**: Windows App from the Mac App Store; set Credentials to **Ask when required** when adding the PC so the xrdp login screen shows (not tested)

## Quick start

### Kubernetes

On a machine with kubectl, curl and bash that can reach the cluster (check the current cluster with `kubectl config current-context`):

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

The script deploys to namespace `rdp-vscode` with your current kubeconfig and prints the address of every node. Connect Remote Desktop to `<node IP>:30390` and log in as `bigred` / `bigred`.

You can also read node IPs from the INTERNAL-IP column of `kubectl get nodes -o wide`; any node works. On a cloud cluster use an IP your client can reach.

- This deployment keeps `/home` in an emptyDir, so settings reset when the Pod restarts. For several accounts, other passwords or a persistent home, use [Advanced](#advanced-several-accounts-and-a-persistent-home-kustomize) below
- If the nodes sit on a host-internal network your LAN cannot reach (tk8s, for example), forward a port on the host: see Step 6 of [docs/build-image.md](docs/build-image.md)
- Uninstall: `kubectl delete namespace rdp-vscode`

### Single host (podman)

```bash
podman run -d --name rdp-vscode -p 13390:3389 --shm-size 1g \
  -e RDP_PASSWORD=bigred -e SSH_HOST=<ssh host> -e SSH_PORT=22 -e SSH_USER=<ssh user> \
  -e SSH_REMOTE_FOLDER=/home/<ssh user> \
  ghcr.io/braveantony/rdp-vscode:1.0
```

Connect Remote Desktop to `<host IP>:13390` (the machine running podman; `localhost:13390` on the same machine) and log in as `bigred` / `bigred`. `--shm-size 1g` enlarges shared memory: with the 64 MB default, VSCodium crashes while loading the CJK fonts.

Without a cluster there is no tkadm, so point `SSH_HOST` and friends at an SSH host (its sshd must allow port forwarding too). To skip the automatic connection, pass `-e SSH_HOST_ALIAS=` (empty) and you get a local VSCodium.

## How to use

### 1. Log in

Press `Win+R`, type `mstsc` and connect to the address above. Accept the certificate warning (each Pod generates its own certificate at startup, so it shows again after the Pod is recreated). On the xrdp login screen keep Session `Xorg`, enter the account and password, and press OK.

![xrdp login screen](docs/images/01-login.png)

### 2. Connect to tkadm

VSCodium opens full screen and asks `Enter password for bigred@tkadm.taroko`. Enter tkadm's password (default `bigred`). When the bottom-left corner shows `SSH: tkadm` and the explorer lists `/home/bigred` on tkadm, you are connected.

![tkadm password prompt](docs/images/02-ssh-password.png)

![Connected to tkadm](docs/images/03-connected.png)

The first connection after tkadm restarts downloads a server of about 90 MB first. Every reconnect, including Reload Window, asks for the password again.

### 3. Deploy a website on tkadm and open it by its cluster name

Press `` Ctrl+` `` for a terminal (it runs on tkadm) and deploy nginx:

```bash
kubectl create deploy web --image=nginx
kubectl expose deploy web --port 80
```

Press `Ctrl+Shift+P`, run "Browser: Open Integrated Browser" (or click the globe icon on the right of the title bar), and enter `http://web.default`. The nginx welcome page shows up.

![Opening a cluster website in the Integrated Browser](docs/images/04-browser.png)

Use the short name `http://<service>.<namespace>` or the full `http://<service>.<namespace>.svc.<cluster domain>`. The cluster domain is not always `cluster.local` (on tk8s it is `tk8s.k8s`); find it with `kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep kubernetes`. Add `:<port>` when the service does not listen on 80.

> `Ctrl`-clicking a URL in the terminal does not open the Integrated Browser, and the default image has no other browser, so nothing happens. The `-firefox` image opens such links in Firefox.

### 4. Good to know

- **Closing VSCodium logs you out**: `Ctrl+Q` or the close button ends the Remote Desktop connection
- **A disconnected desktop cannot be resumed**: reconnecting always gives a new desktop; the old one is removed 2 minutes after the disconnect. Files on tkadm are not affected
- **Typing Chinese**: there is no input method in the Pod; type on your own computer, copy, and paste with `Ctrl+V`
- **Everyone is bigred on tkadm**: all RDP accounts log in to tkadm as the same user and see and change each other's files

More in the [user guide](docs/user-guide.md) (Traditional Chinese).

## Advanced: several accounts and a persistent home (Kustomize)

Accounts are listed in `users.txt`; Kustomize's `secretGenerator` turns it into a Secret mounted at `/etc/rdp-vscode/users`. There are two overlays:

| Overlay | `/home` | When the Pod restarts |
|---|---|---|
| `manifests/stateless` | emptyDir | Files, settings and user-installed extensions are lost |
| `manifests/stateful` | PVC `rdp-vscode-home` (5 GiB, ReadWriteOnce) | Everything under `/home` is kept |

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
vi manifests/stateful/users.txt   # edit the account list with any editor
kubectl apply -k manifests/stateful
kubectl -n rdp-vscode rollout status deploy/rdp-vscode   # wait for the Pod (the first pull is about 1.3 GB)
```

`users.txt` has one `user:password` per line; lines starting with `#` are comments:

```text
alice:Alice-pw
bob:Bob-pw
```

- Names start with a lowercase letter or `_`, use lowercase letters, digits, `_` and `-`, up to 32 characters, and may not be `root`, `xrdp` or an existing system account. Passwords may not be empty and may contain `:`. Windows line endings are fine. On invalid input the Pod fails to start; see why with `kubectl -n rdp-vscode logs deploy/rdp-vscode`.
- Accounts get UIDs 1000, 1001, … in file order. On a stateful deployment, reordering the file hands existing homes to the new UIDs at startup; the home of a removed account is locked to root, so whoever gets its old UID cannot read it.
- After editing `users.txt`, run `kubectl apply -k` again: the Secret name carries a content hash (`rdp-vscode-users-<hash>`), so a changed list recreates the Pod. Every desktop lives in that one Pod, so all sessions end.
- **StorageClass for stateful**: the PVC has no `storageClassName` and uses the cluster default. That class must bind on first use (`volumeBindingMode: WaitForFirstConsumer`, as `local-path` should be) or be network storage. With `Immediate`, `local-path` cannot tell which node to create the volume on and the PVC stays `Pending`. A `local-path` volume lives on one node; if that node is down, the Pod cannot start.
- To replace the SSH configuration entirely (several Hosts, for example), see `manifests/example/ssh-configmap`: a ConfigMap replaces the config built from `SSH_*`.
- To use another image (a private registry or the `-firefox` variant), add an `images:` block with `newName` / `newTag` to the overlay's `kustomization.yaml`.
- `users.txt` holds plain-text passwords; do not commit it to a public repo. Tools such as SOPS or Sealed Secrets can manage it.
- If you used the quick start before, just apply the overlay. Do not run `install.sh` again afterwards; it would reset to bigred/bigred and an emptyDir.

## Images

| | 1.0 | 1.0-firefox |
|---|---|---|
| Image | `ghcr.io/braveantony/rdp-vscode:1.0` | `ghcr.io/braveantony/rdp-vscode:1.0-firefox` |
| VSCodium 1.143.17183, Open Remote-SSH 0.5.1, Traditional Chinese pack 1.131.0 | ✅ | ✅ |
| Auto-connect to tkadm, YAML extension installed on tkadm | ✅ | ✅ |
| Open cluster websites in the Integrated Browser | ✅ | ✅ |
| Firefox ESR: `Ctrl`-clicked URLs open in it, `Alt+Tab` switches windows | — | ✅ |
| Size | about 1.3 GB | about 1.6 GB |

`images/rdp-vscode/Dockerfile` selects the variant with the build argument `WITH_FIREFOX`; `WITH_FIREFOX=1` builds `-firefox`, and only the last layer differs.

## Documentation (Traditional Chinese)

- [architecture.md](docs/architecture.md): how it works (connection path, what each process in the Pod does, security boundaries)
- [user-guide.md](docs/user-guide.md): user guide (logging in, connecting to tkadm, opening websites, concurrent use, troubleshooting)
- [build-image.md](docs/build-image.md): build both tags from source, test them, and deploy to Kubernetes (tk8s)
- [design/](docs/design/README.md): design decisions, acceptance criteria, risks and review history
- [ops/](docs/ops/): changes made to tk8s for this project (tkadm sshd, local-path StorageClass)

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `USERS_FILE` | `/etc/rdp-vscode/users` | Account file, one `user:password` per line; mounted from Secret `rdp-vscode-users-*` on Kubernetes. When it exists and is not empty, the next two variables are ignored |
| `RDP_USER` | `bigred` | Login account when there is no account file (UID 1000) |
| `RDP_PASSWORD` | — | Its password (required in that case) |
| `MAX_SESSIONS` | `3` | Maximum concurrent desktops, all accounts together; each one needs about 1 GiB more memory |
| `SSH_HOST_ALIAS` | `tkadm` | SSH `Host` name VSCodium connects to on login; empty disables the auto connect |
| `SSH_HOST` | `tkadm.taroko` | Host name or IP of the SSH target. The short name (`<service>.<namespace>`) works with any cluster domain |
| `SSH_PORT` | `22100` | SSH port |
| `SSH_USER` | `bigred` | SSH user |
| `SSH_REMOTE_FOLDER` | `/home/<SSH_USER>` | Folder opened on the SSH target |
| `VSCODIUM_LOCALE` | `zh-tw` | UI language: `zh-tw` or `en` |

The SSH config is written to `/etc/ssh/ssh_config.d/rdp-vscode.conf`. A mounted, non-empty ConfigMap `rdp-vscode-ssh` (key `config`) replaces it entirely.

## Files

| Path | Contents |
|---|---|
| `VERSION` | Current version |
| `images/rdp-vscode/Dockerfile` | Image definition (base `debian:trixie-slim`; `WITH_FIREFOX=1` adds Firefox ESR) |
| `images/rdp-vscode/rootfs/` | Config files and scripts copied to `/` in the image (entrypoint, accounts, SSH config, session start and cleanup) |
| `images/rdp-vscode/rootfs-firefox/` | Files used only by the `-firefox` variant |
| `install.sh` | Quick-start `curl \| bash` installer (bigred/bigred, `/home` in an emptyDir) |
| `manifests/base/` | Kustomize base: Namespace, Deployment, NodePort Service (30390) |
| `manifests/stateless/`, `manifests/stateful/` | Overlays: Secret from `users.txt`; `/home` in an emptyDir or a PVC |
| `manifests/example/ssh-configmap/` | Example of replacing the SSH config with a ConfigMap |
| `docs/` | Architecture, user guide, build guide, diagram (`docs/architecture/`), README screenshots (`docs/images/`), design docs |
| `test/` | Unit, image and deploy tests, and the end-to-end acceptance on tk8s (`test/e2e/`) |

## License

[Apache-2.0](LICENSE)
