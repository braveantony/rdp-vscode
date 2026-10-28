# rdp-vscode

[繁體中文](README.md)

Log in with Windows Remote Desktop (RDP) and you get a full-screen VSCodium (the open-source build of VS Code) running inside your Kubernetes cluster. It connects over SSH to the cluster's admin Pod, tkadm, on its own, so you edit files and run `kubectl` there. Several people can use it at once, and every login gets its own desktop (up to 3 at a time, adjustable).

## Overview

- **Code and run the cluster from inside it**: the VSCodium you use after logging in runs in the cluster
  - **Editor and CLI**: connects to tkadm over SSH (Open Remote-SSH); the explorer and the terminal are on tkadm, and the kubeconfig (kubectl's cluster credentials) never leaves the cluster
  - **Web**: open `http://<service>.<namespace>` (for example `http://web.default`) in the built-in Integrated Browser to reach web services inside the cluster
  - Only one NodePort (a fixed port Kubernetes opens on every node; here 30390) is exposed; nothing else needs to be opened to the outside
- **Nothing to install**: the Remote Desktop client built into Windows is enough; no local VS Code or extensions
- **Concurrent use**: several accounts, or the same account several times, can be logged in at once; every login has its own desktop and VSCodium. Different accounts cannot see each other's home in this Pod (but they are the same user on tkadm)
- **Chinese UI and YAML completion**: the Traditional Chinese language pack is preinstalled; the YAML extension is installed on tkadm on first connect, so Kubernetes YAML gets field completion
- **Persistent settings** (stateful mode): `/home` lives on a PVC (persistent storage requested from the cluster), so VSCodium settings and locally installed extensions survive the Pod being recreated

## Architecture

![rdp-vscode architecture](docs/architecture/rdp-vscode-architecture.png)

The client connects over RDP to NodePort `30390` on any node; Service `rdp-vscode` forwards it to port 3389 of the Pod. The Pod has a single container with these processes and sessions:

- ① xrdp / xrdp-sesman: accept RDP connections, show the login screen, check the account, and open a new desktop for every login
- ② Xorg session: one desktop per login, running VSCodium full screen; closing VSCodium logs you out
- VSCodium connects over SSH to tkadm in namespace `taroko` (`tkadm.taroko:22100`) and starts ③ vscodium-server there, so files and terminals are on tkadm

Details in [docs/architecture.md](docs/architecture.md) (Traditional Chinese).

## Prerequisites

### Kubernetes cluster

- kubectl, curl, bash (and git to install with Kustomize). kubectl includes Kustomize, used by `kubectl apply -k`
- A kubeconfig (usually `~/.kube/config`) allowed to create and update Namespaces, Deployments, Services and Secrets (plus PersistentVolumeClaims for stateful), read Deployments and Services, list and delete old `rdp-vscode-users-*` Secrets in namespace `rdp-vscode`, and list Nodes (`install.sh` needs all of these)
- Nodes that can pull from `ghcr.io` (the image is about 1.3 GB)
- Resources: the Pod requests 0.5 CPU / 1 GiB and is limited to 4 CPU / 4 GiB (sized for 3 concurrent users)
- NodePort `30390` free, and clients able to reach TCP 30390 on the nodes
- **SSH target**: by default the cluster admin Pod tkadm in namespace `taroko` (`tkadm.taroko:22100`, with kubectl and a kubeconfig). tkadm is deployed separately; this repo does not provide it. It needs:
  - an sshd that allows port forwarding, see [docs/ops/2026-10-27-tkadm-sshd-forwarding.md](docs/ops/2026-10-27-tkadm-sshd-forwarding.md)
  - access to `github.com` and `open-vsx.org`: on first connect tkadm downloads vscodium-server and the YAML extension itself
  - for another host, change the `SSH_*` [environment variables](#environment-variables)

### Remote Desktop client

- **Windows**: the built-in Remote Desktop Connection (`mstsc`)
- **macOS**: Windows App from the Mac App Store; set Credentials to **Ask when required** when adding the PC so the xrdp login screen shows (not tested)

## Quick start

On a machine with kubectl, curl and bash that can reach the cluster:

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

The script deploys to namespace `rdp-vscode` and prints the address of every node. Connect Remote Desktop to `<node IP>:30390` and log in as `bigred` / `bigred`.

This quick install has one account and keeps no settings. Several accounts, your own passwords or a persistent home (Kustomize), a single host with podman when there is no Kubernetes, LAN access when the nodes sit on an internal network, and uninstalling are all in the [install guide](docs/install.md) (Traditional Chinese).

## How to use

### 1. Log in

Press `Win+R`, type `mstsc` and connect to the address above. Accept the certificate warning (each Pod generates its own certificate at startup, so the warning shows again after the Pod is recreated). On the xrdp login screen keep Session `Xorg`, enter the account and password, and press OK.

![xrdp login screen](docs/images/01-login.png)

### 2. Connect to tkadm

VSCodium opens full screen and asks `Enter password for bigred@tkadm.taroko`. Enter the SSH password of `bigred` on tkadm (`bigred` on tk8s). When the bottom-left corner shows `SSH: tkadm` and the explorer lists `/home/bigred` on tkadm, you are connected.

![tkadm password prompt](docs/images/02-ssh-password.png)

![Connected to tkadm](docs/images/03-connected.png)

When tkadm does not have this version of vscodium-server yet (first connection, after tkadm is recreated, or after an image upgrade), tkadm first downloads about 90 MB. Every reconnect, including Reload Window, asks for the password again.

### 3. Deploy a website on tkadm and open it by its cluster name

Press `` Ctrl+` `` for a terminal (it runs on tkadm) and deploy nginx in namespace `default` (pick another name if `default` already has something called `web`):

```bash
kubectl -n default create deploy web --image=nginx
kubectl -n default expose deploy web --port 80
```

Press `Ctrl+Shift+P`, run "Browser: Open Integrated Browser" (or click the globe icon on the right of the title bar), and enter `http://web.default`. The nginx welcome page shows up.

![Opening a cluster website in the Integrated Browser](docs/images/04-browser.png)

Use the short name `http://<service>.<namespace>` or the full domain name (see the [user guide](docs/user-guide.md)). Add `:<port>` when the service does not listen on 80.

> `Ctrl`-clicking a URL in the terminal does not open the Integrated Browser, and the 1.0 image has no other browser, so nothing happens. The `-firefox` image opens such links in Firefox.

### 4. Good to know

- **Closing VSCodium logs you out**: `Ctrl+Q` or the close button ends the Remote Desktop connection
- **A disconnected desktop cannot be resumed**: reconnecting always gives a new desktop; the old one is closed 2 minutes after the disconnect and **unsaved changes are lost**. Saved files on tkadm are not affected
- **Typing Chinese**: there is no input method in the Pod; type on your own computer, copy, and paste with `Ctrl+V`
- **Everyone is bigred on tkadm**: all RDP accounts log in to tkadm as the same user and see and change each other's files

More in the [user guide](docs/user-guide.md) (Traditional Chinese).

## Images

| | 1.0 | 1.0-firefox |
|---|---|---|
| Image | `ghcr.io/braveantony/rdp-vscode:1.0` | `ghcr.io/braveantony/rdp-vscode:1.0-firefox` |
| VSCodium 1.143.17183, Open Remote-SSH 0.5.1, Traditional Chinese pack 1.131.0 | ✅ | ✅ |
| Auto-connect to tkadm, YAML extension installed on tkadm | ✅ | ✅ |
| Open cluster websites in the Integrated Browser | ✅ | ✅ |
| Firefox ESR (`Ctrl`-clicked URLs in the terminal open in it, `Alt+Tab` switches windows) | — | ✅ |
| Size | about 1.3 GB | about 1.6 GB |

`images/rdp-vscode/Dockerfile` selects the variant with the build argument `WITH_FIREFOX`; `WITH_FIREFOX=1` builds `-firefox`, and only the last layer differs. See [Releases](../../releases) for the notes of each version.

## Documentation (Traditional Chinese)

- [install.md](docs/install.md): installation (quick install, Kustomize with several accounts and a persistent home, single-host podman, LAN access, uninstall)
- [architecture.md](docs/architecture.md): how it works (connection path, what each process in the Pod does, security boundaries)
- [user-guide.md](docs/user-guide.md): user guide (logging in, connecting to tkadm, opening websites, concurrent use, troubleshooting)
- [build-image.md](docs/build-image.md): build guide (build both tags from source, test them, and deploy to Kubernetes on tk8s)
- [design/](docs/design/README.md): design decisions, acceptance criteria, risks and review history
- [ops/](docs/ops/): changes made to tk8s for this project (tkadm sshd, local-path StorageClass)

## Environment variables

Edit `env` in `manifests/base/deployment.yaml` and run `kubectl apply -k` again.

| Variable | Default | Meaning |
|---|---|---|
| `USERS_FILE` | `/etc/rdp-vscode/users` | Account file, one `user:password` per line; on Kubernetes it is always mounted from Secret `rdp-vscode-users-*` |
| `RDP_USER` | `bigred` | Login account when there is no account file (UID 1000); on Kubernetes the file always exists, so it is not used |
| `RDP_PASSWORD` | — | Its password, required in that case; not used on Kubernetes |
| `MAX_SESSIONS` | `3` | Maximum concurrent desktops, all accounts together (a disconnected desktop counts until it is removed 2 minutes later); each one needs about 1 GiB more memory |
| `SSH_HOST_ALIAS` | `tkadm` | SSH `Host` name VSCodium connects to on login; empty disables the auto connect |
| `SSH_HOST` | `tkadm.taroko` | Host name or IP of the SSH target. The short name (`<service>.<namespace>`) works with any cluster domain |
| `SSH_PORT` | `22100` | SSH port |
| `SSH_USER` | `bigred` | SSH user |
| `SSH_REMOTE_FOLDER` | `/home/<SSH_USER>` | Folder opened on the SSH target. `manifests/base/deployment.yaml` sets it to `/home/bigred` explicitly; change both together |
| `VSCODIUM_LOCALE` | `zh-tw` | UI language: `zh-tw` or `en` |

The SSH config is written to `/etc/ssh/ssh_config.d/rdp-vscode.conf`. A mounted, non-empty ConfigMap `rdp-vscode-ssh` (key `config`) replaces it entirely; it must then contain a `Host` named like `SSH_HOST_ALIAS`.

## Files

| Path | Contents |
|---|---|
| `VERSION` | Current version |
| `images/rdp-vscode/Dockerfile` | Image definition (base `debian:trixie-slim`; `WITH_FIREFOX=1` adds Firefox ESR) |
| `images/rdp-vscode/rootfs/` | Config files and scripts copied to `/` in the image (entrypoint, accounts, SSH config, desktop start and cleanup) |
| `images/rdp-vscode/rootfs-firefox/` | Files used only by the `-firefox` variant |
| `install.sh` | Quick-install `curl \| bash` installer (`bigred` / `bigred`, `/home` in an emptyDir) |
| `manifests/base/` | Kustomize base: Namespace, Deployment, NodePort Service (30390) |
| `manifests/stateless/`, `manifests/stateful/` | Overlays: Secret from `users.txt`; `/home` in an emptyDir or a PVC |
| `manifests/example/ssh-configmap/` | Example of replacing the SSH config with a ConfigMap |
| `docs/` | Architecture, user guide, build guide, diagram (`docs/architecture/`), README screenshots (`docs/images/`), design docs |
| `test/` | Unit, image and deploy tests, and the end-to-end acceptance on tk8s (`test/e2e/`) |

## Security warning

The default account `bigred` / `bigred` is for isolated lab clusters only. Anyone who can reach NodePort 30390 with it gets into the cluster network, can SSH to tkadm, and through `kubectl` there controls the whole cluster. Before you deploy anywhere else, switch to [several accounts](docs/install.md#kustomize多個帳號與保留-home) with your own passwords.

## License

[Apache-2.0](LICENSE)
