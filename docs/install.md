# rdp-vscode 安裝手冊

適用映像檔：`ghcr.io/braveantony/rdp-vscode:1.0`（`:1.0-firefox` 的安裝方式相同，只要換 tag）。先決條件見 [README](../README.md#先決條件)。

## 選擇安裝方式

| 方式 | 適合 | 帳號 | `/home` |
|---|---|---|---|
| [快速安裝](#快速安裝installsh) | 先試用看看 | 只有 `bigred` / `bigred` | emptyDir（Pod 重建後回到預設值） |
| [Kustomize：stateless](#kustomize多個帳號與保留-home) | 多人使用，但不需要保留設定 | 自己的帳號清單 | emptyDir |
| [Kustomize：stateful](#kustomize多個帳號與保留-home) | 多人使用，而且要保留設定 | 自己的帳號清單 | PVC（向叢集申請的永久儲存空間） |
| [單機（podman）](#單機podman) | 沒有 Kubernetes，只想在一台 Linux 主機上用 | 單一帳號，或掛載帳號清單 | container 裡（刪掉 container 就消失） |

前三種都部署到 namespace `rdp-vscode`，用遠端桌面連到 `<節點 IP>:30390`。

## 快速安裝（install.sh）

在已安裝 kubectl、curl、bash，而且連得到目標叢集的電腦上執行（可以先用 `kubectl config current-context` 確認目前選用的是哪個叢集）：

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

腳本會部署單一帳號 `bigred` / `bigred`，完成後印出每個節點的連線位址。節點 IP 也可以用 `kubectl get nodes -o wide` 的 INTERNAL-IP 欄查看；雲端叢集要用用戶端連得到的 IP。

`install.sh` 也可以用環境變數調整，主要給測試用：

| 變數 | 說明 |
|---|---|
| `RDP_VSCODE_REF` | 要部署的 branch 或 tag，預設 `main` |
| `RDP_VSCODE_IMAGE` | 改用其他映像檔，例如 `ghcr.io/braveantony/rdp-vscode:1.0-firefox` |
| `RDP_VSCODE_RAW` | 從哪裡下載 `manifests/`，預設是 GitHub |

例如改裝 `-firefox` 版：

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | RDP_VSCODE_IMAGE=ghcr.io/braveantony/rdp-vscode:1.0-firefox bash
```

## Kustomize：多個帳號與保留 home

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
vi manifests/stateful/users.txt   # 修改帳號清單，一行一個「帳號:密碼」
kubectl apply -k manifests/stateful   # 不需要保留設定時改用 manifests/stateless
kubectl -n rdp-vscode rollout status deploy/rdp-vscode   # 第一次要下載約 1.3 GB
```

帳號規則、修改帳號清單時會發生什麼、stateful 需要的 StorageClass、換映像檔和環境變數的方法，都寫在 [README 的「進階」](../README.md#進階多個帳號與保留-homekustomize)。

已經用快速安裝裝過也沒關係，直接 `kubectl apply -k` 就會改用新的設定；之後不要再執行 `install.sh`，否則會還原成 `bigred` / `bigred` 和 emptyDir。

## 單機（podman）

沒有 Kubernetes 時，可以在一台 Linux 主機上用 podman（類似 Docker 的容器工具）直接執行。單機沒有叢集，連不到預設的 tkadm，所以要用 `SSH_HOST` 等變數指定一台 SSH 主機；它的 sshd 一樣要允許埠轉發（`AllowTcpForwarding local` 或 `yes`）。

先把 `<SSH 主機>`、`<SSH 帳號>` 連同尖括號換成實際的值（例如 `192.168.1.10`、`alice`），再貼上：

```bash
podman run -d --name rdp-vscode -p 13390:3389 --shm-size 1g \
  -e RDP_PASSWORD=bigred -e SSH_HOST=<SSH 主機> -e SSH_PORT=22 -e SSH_USER=<SSH 帳號> \
  -e SSH_REMOTE_FOLDER=/home/<SSH 帳號> \
  ghcr.io/braveantony/rdp-vscode:1.0
```

用遠端桌面連到 `<主機 IP>:13390`（執行 podman 的那台機器；在同一台機器上可以用 `localhost:13390`），帳號 `bigred`、密碼 `bigred`。

- `--shm-size 1g` 用來加大共用記憶體，因為用預設的 64 MB 時，VSCodium 載入中文字型會崩潰。
- **多個帳號**：把帳號清單掛載進去，取代 `RDP_PASSWORD`：在映像檔名稱之前加上 `-v ./users.txt:/etc/rdp-vscode/users:ro,Z`（`ro` 表示唯讀，`Z` 是給 SELinux 系統用的標記，沒有 SELinux 也不影響）。`users.txt` 的格式和 Kubernetes 版相同。
- **不自動連線**：改成 `-e SSH_HOST_ALIAS=`（空字串），登入後只開啟 container 裡的 VSCodium，不會連到任何 SSH 主機。
- 檔案和設定都在 container 裡，刪掉 container（`podman rm -f rdp-vscode`）就會消失。
- 其他環境變數見 [README 的「環境變數」](../README.md#環境變數)。

## 從區網連線（節點在內部網段時）

如果 Kubernetes 的節點位在主機的內部網段，區網連不到 NodePort（例如 tk8s，節點是主機上的 podman container），就在主機上用 socat（把一個埠的連線轉送到另一個位址的小工具）把主機的埠轉到任一節點的 30390：

```bash
podman run -d --name rdp-vscode-forward --restart=always --network host \
  docker.io/alpine/socat:1.8.0.3 TCP-LISTEN:3390,fork,reuseaddr TCP:<節點 IP>:30390
```

之後用遠端桌面連到 `<主機 IP>:3390`。rootless podman 的 container 要在你登出或主機重開機後仍會自動啟動，需要執行一次：

```bash
sudo loginctl enable-linger $USER
systemctl --user enable podman-restart.service
```

## 移除

| 安裝方式 | 指令 |
|---|---|
| 快速安裝、Kustomize | `kubectl delete namespace rdp-vscode`（stateful 模式的 PVC 會一起刪除；StorageClass 的 reclaimPolicy 是 `Delete` 時，`/home` 的資料也會跟著消失） |
| 單機 | `podman rm -f rdp-vscode` |
| 區網轉發 | `podman rm -f rdp-vscode-forward` |

> 本文件的指令已於 2026-10-28 實測：快速安裝與 Kustomize（stateless、stateful）在 tk8s 上部署並以 RDP 登入；單機以掛載帳號清單的方式啟動，用其中一個帳號登入並開出自己的 VSCodium；區網轉發以 `192.168.11.64:3390` 登入。`RDP_VSCODE_IMAGE` 改裝 `-firefox` 版尚未實測。
