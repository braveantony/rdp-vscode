# rdp-vscode

[繁體中文](README.md)

Use Windows Remote Desktop to connect to your Kubernetes cluster and you get a full-screen VSCodium (an open-source build of VS Code). It automatically connects over SSH (an encrypted remote connection) to the cluster's admin Pod, tkadm, where you edit files and run `kubectl`. New to Kubernetes? A Pod is the unit the cluster runs programs in, `kubectl` is the command-line tool for managing the cluster, and a namespace groups resources.

Several people can use it at once, and each login gets its own desktop. The default limit is 3 desktops at a time, and you can change it.

## Overview

- After you log in, VSCodium runs in the cluster and its Open Remote-SSH extension connects to tkadm over SSH automatically. The file explorer and terminal are on tkadm, so the kubeconfig (the settings `kubectl` uses to reach the cluster) never leaves the cluster.
- Open `http://<service>.<namespace>` (for example `http://web.default`) in the built-in Integrated Browser to reach web services inside the cluster.
- Only one NodePort (a fixed port Kubernetes opens on every node; here 30390) is exposed; nothing else is opened to the outside.
- The Remote Desktop client built into Windows is enough. You don't need to install VS Code or extensions on your own computer.
- Several accounts, or the same account more than once, can be logged in at the same time. Accounts cannot see each other's home directories in this Pod, but they are all the same user on tkadm.
- The Traditional Chinese language pack is preinstalled. The YAML extension is installed on tkadm automatically on the first connection, so you get field completion when editing Kubernetes YAML.
- To keep your settings, use stateful mode: `/home` lives on a PVC (persistent storage requested from the cluster), so VSCodium settings and extensions installed in the Pod survive when the Pod is recreated.

## Architecture

![rdp-vscode architecture](docs/architecture/rdp-vscode-architecture.png)

The client connects over the Remote Desktop Protocol (RDP) to NodePort `30390` on a node, and Service `rdp-vscode` forwards the connection to port 3389 of the Pod. The Pod has a single container, running these processes (programs) and sessions (the group of processes behind one desktop):

- ① xrdp / xrdp-sesman: accept RDP connections, show the login screen, check the account, and open a new desktop for every login
- ② Xorg session: one desktop per login, running VSCodium full screen; closing VSCodium logs you out
- ③ vscodium-server: the server side of VSCodium, started on tkadm after VSCodium connects over SSH to tkadm in namespace `taroko` (`tkadm.taroko:22100`); files and terminals are on tkadm

Details in [docs/architecture.md](docs/architecture.md) (Traditional Chinese).

## Prerequisites

### Kubernetes cluster

- kubectl, curl, bash (and git to install with Kustomize). kubectl already includes Kustomize, a tool for assembling YAML manifests; `kubectl apply -k` uses it
- A kubeconfig (usually `~/.kube/config`) with enough permission for `install.sh`: create and update Namespaces, Deployments, Services and Secrets (Kubernetes objects that hold passwords and other sensitive data; plus PVCs for stateful mode), read Deployments and Services, list Nodes, and list and delete old `rdp-vscode-users-*` Secrets in namespace `rdp-vscode`
- Nodes that can pull from `ghcr.io` (the image is about 1.3 GB)
- Resources: the Pod requests 0.5 CPU / 1 GiB and is limited to 4 CPU / 4 GiB (sized for 3 concurrent users)
- NodePort `30390` free, and clients able to reach TCP 30390 on the nodes (open it in the firewall if needed)
- The SSH target is by default the cluster admin Pod tkadm in namespace `taroko` (`tkadm.taroko:22100`, with kubectl and a kubeconfig). tkadm is deployed separately; this repo does not provide it. It needs:
  - an sshd (SSH server) that allows port forwarding, that is, relaying other network connections through the SSH connection (see [docs/ops/2026-10-27-tkadm-sshd-forwarding.md](docs/ops/2026-10-27-tkadm-sshd-forwarding.md), Traditional Chinese)
  - access to `github.com` and `open-vsx.org`: on the first connection, tkadm itself downloads vscodium-server and the YAML extension
- To connect to another host, change the `SSH_*` [environment variables](#environment-variables)

### Remote Desktop client

- **Windows**: the built-in Remote Desktop Connection (`mstsc`)
- **macOS**: Windows App from the Mac App Store; set Credentials to **Ask when required** when adding the PC so the xrdp login screen shows (not tested)

## Quick start

On a machine with kubectl, curl and bash that can reach the cluster:

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

The script deploys to namespace `rdp-vscode` and prints the address of every node. Connect Remote Desktop to `<node IP>:30390` and log in as `bigred` / `bigred`.

This quick install has one account and keeps no settings. Several accounts, your own passwords or a persistent home (all three need the Kustomize deployment), single-host podman when there is no Kubernetes, LAN access when the nodes sit on an internal network, and uninstalling are all in the [install guide](docs/install.md) (Traditional Chinese).

## How to use

### 1. Log in

Press `Win+R`, type `mstsc` and connect to the address above. Accept the certificate warning. Each Pod generates its own certificate at startup, so the warning appears again after the Pod is recreated. On the xrdp login screen, keep Session set to `Xorg`, enter the account and password, and press OK.

![xrdp login screen](docs/images/01-login.png)

### 2. Connect to tkadm

VSCodium opens full screen and asks `Enter password for bigred@tkadm.taroko`. Enter the SSH password for `bigred` on tkadm, then press Enter. This is a second password, set on tkadm: on tk8s, the test cluster of this project, it is `bigred`; elsewhere, ask your administrator. You are connected when the bottom-left corner shows `SSH: tkadm` and the explorer lists `/home/bigred` on tkadm.

![tkadm password prompt](docs/images/02-ssh-password.png)

![Connected to tkadm](docs/images/03-connected.png)

If tkadm does not have this version of vscodium-server yet (first connection, after tkadm is recreated, or after the image changed to a different VSCodium version), tkadm first downloads about 90 MB from `github.com`, so expect a short wait. Every reconnect, including Reload Window, asks for the password again.

### 3. Deploy a website on tkadm and open it by its cluster name

Press `` Ctrl+` `` to open a terminal (it runs on tkadm) and deploy nginx in namespace `default` (pick another name if `default` already has something called `web`):

```bash
kubectl -n default create deploy web --image=nginx
kubectl -n default expose deploy web --port 80
```

Press `Ctrl+Shift+P`, run "Browser: Open Integrated Browser" (or click the globe icon on the right of the title bar), and enter `http://web.default`. The nginx welcome page shows up.

![Opening a cluster website in the Integrated Browser](docs/images/04-browser.png)

Use the short name `http://<service>.<namespace>` or the full domain name (see the [user guide](docs/user-guide.md), Traditional Chinese). Add `:<port>` when the service does not listen on 80.

> `Ctrl`-clicking a URL in the terminal does not open the Integrated Browser, and the 1.0 image has no other browser, so nothing happens. The `-firefox` image opens such links in Firefox.

### 4. Good to know

- Close VSCodium with `Ctrl+Q` or the close button to log out and end the Remote Desktop connection.
- A disconnected desktop cannot be resumed: reconnecting always opens a new one, and the old desktop closes 2 minutes after the disconnect, so **unsaved changes are lost**. Files already saved on tkadm are unaffected.
- The Pod has no Chinese input method. Type and copy text on your own computer, then paste it in VSCodium with `Ctrl+V`.
- All RDP accounts connect to tkadm as the same user, bigred. They can see and change each other's files.

The [user guide](docs/user-guide.md) (Traditional Chinese) has the full instructions and troubleshooting.

## Images

| | 1.0 | 1.0-firefox |
|---|---|---|
| Image | `ghcr.io/braveantony/rdp-vscode:1.0` | `ghcr.io/braveantony/rdp-vscode:1.0-firefox` |
| VSCodium 1.143.17183, Open Remote-SSH 0.5.1, Traditional Chinese pack 1.131.0 | ✅ | ✅ |
| Auto-connect to tkadm, YAML extension installed on tkadm | ✅ | ✅ |
| Open cluster websites in the Integrated Browser | ✅ | ✅ |
| Firefox ESR (`Ctrl`-clicked URLs in the terminal open in it, `Alt+Tab` switches windows) | — | ✅ |
| Size | about 1.3 GB | about 1.6 GB |

`images/rdp-vscode/Dockerfile` selects the variant with the build argument `WITH_FIREFOX`; `WITH_FIREFOX=1` builds `-firefox`, and only the last layer differs. See [Releases](../../releases) for each version's release notes.

## Documentation (Traditional Chinese)

- [install.md](docs/install.md): installation (quick install, Kustomize with several accounts and a persistent home, single-host podman, LAN access, uninstall)
- [architecture.md](docs/architecture.md): how it works (connection path, what each process in the Pod does, security boundaries)
- [user-guide.md](docs/user-guide.md): user guide (logging in, connecting to tkadm, opening websites, concurrent use, troubleshooting)
- [build-image.md](docs/build-image.md): build guide (build both tags from source, test them, and deploy to tk8s)
- [design/](docs/design/README.md): design decisions, acceptance criteria, risks and review history
- [ops/](docs/ops/): changes made to tk8s for this project (tkadm sshd, local-path StorageClass)

## Environment variables

First clone this repo as described in the [install guide](docs/install.md#kustomize多個帳號與保留-home), edit `env` in `manifests/base/deployment.yaml`, and run `kubectl apply -k manifests/stateless` (or `manifests/stateful`, whichever you use) again.

| Variable | Default | Meaning |
|---|---|---|
| `USERS_FILE` | `/etc/rdp-vscode/users` | Account file, one `user:password` per line; on Kubernetes it is always mounted from Secret `rdp-vscode-users-*` |
| `RDP_USER` | `bigred` | Login account when there is no account file (UID 1000); on Kubernetes the file always exists, so it is not used |
| `RDP_PASSWORD` | — | Its password, required in that case; not used on Kubernetes |
| `MAX_SESSIONS` | `3` | Maximum concurrent desktops, all accounts together (a disconnected desktop counts until it is removed 2 minutes later); each one needs about 1 GiB more memory |
| `SSH_HOST_ALIAS` | `tkadm` | SSH `Host` name VSCodium connects to on login; an empty value disables the automatic connection |
| `SSH_HOST` | `tkadm.taroko` | Host name or IP of the SSH target; the default is the short name (`<service>.<namespace>`), so you don't need to know the cluster domain (usually `cluster.local`) |
| `SSH_PORT` | `22100` | SSH port |
| `SSH_USER` | `bigred` | SSH user |
| `SSH_REMOTE_FOLDER` | `/home/<SSH_USER>` | Folder opened on the SSH target; `manifests/base/deployment.yaml` sets it to `/home/bigred` explicitly, so change it as well when you change `SSH_USER` |
| `VSCODIUM_LOCALE` | `zh-tw` | UI language: `zh-tw` or `en` |

The SSH config is written to `/etc/ssh/ssh_config.d/rdp-vscode.conf`. If a ConfigMap `rdp-vscode-ssh` (key `config`) is mounted and not empty, it replaces the whole file; it must then contain a `Host` entry whose name matches `SSH_HOST_ALIAS`.

## Files

| Path | Contents |
|---|---|
| `VERSION` | Current version |
| `images/rdp-vscode/Dockerfile` | Image definition (base `debian:trixie-slim`; `WITH_FIREFOX=1` adds Firefox ESR) |
| `images/rdp-vscode/rootfs/` | Config files and scripts copied to `/` in the image (entrypoint, accounts, SSH config, desktop start and cleanup) |
| `images/rdp-vscode/rootfs-firefox/` | Files used only by the `-firefox` variant |
| `install.sh` | Quick-install `curl \| bash` script (account and password both `bigred`, `/home` in an emptyDir) |
| `manifests/base/` | Kustomize base (shared settings): Namespace, Deployment, NodePort Service (30390) |
| `manifests/stateless/`, `manifests/stateful/` | Overlays: both build the Secret from `users.txt`; `/home` is an emptyDir (stateless) or a PVC (stateful) |
| `manifests/example/ssh-configmap/` | Example of replacing the SSH config with a ConfigMap |
| `docs/` | Architecture, user guide, build guide, diagram (`docs/architecture/`), README screenshots (`docs/images/`), design docs |
| `test/` | Unit, image and deploy tests, and the end-to-end acceptance on tk8s (`test/e2e/`) |

## Security warning

The default account `bigred` / `bigred` is for isolated lab clusters only. Anyone who can reach NodePort 30390 can use it to get into the cluster network, SSH to tkadm, and control the whole cluster with the `kubectl` there. Before you deploy anywhere else, switch to [several accounts](docs/install.md#kustomize多個帳號與保留-home) (Traditional Chinese) with your own passwords.

## License

[Apache-2.0](LICENSE)
