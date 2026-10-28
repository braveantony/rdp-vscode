# rdp-vscode 安裝手冊

適用映像檔：`ghcr.io/braveantony/rdp-vscode:1.0`。`-firefox` 版的安裝方式相同，只有換映像檔的方法依安裝方式而不同，見各節。先決條件見 [README](../README.md#先決條件)。

## 選擇安裝方式

| 方式 | 適合 | 帳號 | `/home` |
|---|---|---|---|
| [快速安裝](#快速安裝installsh) | 先試用看看 | 只有 `bigred` / `bigred` | emptyDir |
| [Kustomize：stateless](#kustomize多個帳號與保留-home) | 多人使用，但不需要保留設定 | 自己的帳號清單 | emptyDir |
| [Kustomize：stateful](#kustomize多個帳號與保留-home) | 多人使用，而且要保留設定 | 自己的帳號清單 | PVC（向叢集申請的永久儲存空間） |
| [單機（podman）](#單機podman) | 沒有 Kubernetes，只想在一台 Linux 主機上用 | 單一帳號，或掛載帳號清單 | container 裡（刪掉 container 就消失） |

emptyDir 是 Pod 刪掉就跟著消失的暫存空間，所以 Pod 重建後（例如重新部署）設定會回到預設值。

前三種都部署到 namespace（Kubernetes 用來分組資源的名稱）`rdp-vscode`，用遠端桌面連到 `<節點 IP>:30390`。登入步驟和操作見 [README 的「怎麼用」](../README.md#怎麼用)。

## 快速安裝（install.sh）

在已安裝 kubectl、curl、bash，而且連得到目標叢集的電腦上執行（可以先用 `kubectl config current-context` 確認目前選用的是哪個叢集）：

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

腳本會部署單一帳號 `bigred` / `bigred`，完成後印出每個節點的連線位址。節點 IP 也可以用 `kubectl get nodes -o wide` 的 INTERNAL-IP 欄查看，連任何一個節點都可以；雲端叢集則要改成用戶端連得到的 IP（例如節點的外部 IP）。

平常不需要設定任何變數。要改裝 `-firefox` 版時，用 `RDP_VSCODE_IMAGE`：

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | RDP_VSCODE_IMAGE=ghcr.io/braveantony/rdp-vscode:1.0-firefox bash
```

`install.sh` 讀取的變數：

| 變數 | 說明 |
|---|---|
| `RDP_VSCODE_IMAGE` | 改用其他映像檔，例如 `ghcr.io/braveantony/rdp-vscode:1.0-firefox` 或私有 registry 上的映像檔 |
| `RDP_VSCODE_REF` | 下載 `manifests/` 時用的 branch 或 tag，決定部署哪個版本的設定和映像檔；預設 `main`。主要給測試用 |
| `RDP_VSCODE_RAW` | `manifests/` 的下載位置，可以是網址或 `file://` 路徑；預設是 GitHub 上 `RDP_VSCODE_REF` 指定的版本，設定後 `RDP_VSCODE_REF` 就沒有作用。主要給測試用 |

移除：`kubectl delete namespace rdp-vscode`。

## Kustomize：多個帳號與保留 home

帳號清單寫在 `users.txt`，由 Kustomize 的 `secretGenerator` 產生 Secret（Kubernetes 存放密碼等敏感資料的物件），掛載到 container 的 `/etc/rdp-vscode/users`。有兩種 overlay（在共用的基本設定上再加的修改，例如 `/home` 要用哪種儲存空間）：

| Overlay | `/home` | Pod 重建時 |
|---|---|---|
| `manifests/stateless` | emptyDir | VSCodium 的設定和本機端安裝的擴充功能都會消失（tkadm 上的檔案不受影響） |
| `manifests/stateful` | PVC `rdp-vscode-home`（5 GiB，ReadWriteOnce） | `/home` 底下的內容都會保留 |

兩個資料夾各有自己的 `users.txt`，**要編輯的是你接下來要套用的那個資料夾裡的檔案**。

在快速安裝用的那台電腦上執行，另外需要 git：

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
vi manifests/stateful/users.txt   # 用你熟悉的文字編輯器修改帳號清單，這裡以 vi 為例
kubectl apply -k manifests/stateful
kubectl -n rdp-vscode rollout status deploy/rdp-vscode   # 等待 Pod 啟動完成（第一次要下載約 1.3 GB）
```

不需要保留設定時，把上面兩處的 `manifests/stateful` 都換成 `manifests/stateless`。完成後用遠端桌面連到 `<節點 IP>:30390`，以 `users.txt` 裡的帳號登入。

已經用快速安裝裝過也沒關係，直接執行 `kubectl apply -k` 就會改用新的設定；之後不要再執行 `install.sh`，否則會還原成 `bigred` / `bigred` 和 emptyDir。

### 帳號清單

`users.txt` 一行一個 `帳號:密碼`，`#` 開頭是註解：

```text
alice:Alice-pw
bob:Bob-pw
```

- 帳號規則：小寫英文字母或 `_` 開頭，可以用小寫英數字、`_`、`-`，最長 32 字元，不可以是 `root`、`xrdp` 或系統既有的帳號；密碼不可空白，可以包含冒號。檔案在 Windows 上編輯（CRLF 換行）也沒關係。不符規則時 Pod 會啟動失敗，原因可以用 `kubectl -n rdp-vscode logs deploy/rdp-vscode` 查看。
- 帳號依檔案順序分配 UID（Linux 的使用者編號）1000、1001……。在 stateful 模式下調換順序，Pod 啟動時會把既有的 home 改歸新的 UID 所有；被移除帳號的 home 會改由 root 擁有，之後分到同一個 UID 的帳號也讀不到。
- 修改 `users.txt` 後再執行一次 `kubectl apply -k` 即可。因為 Secret 名稱帶有內容雜湊（`rdp-vscode-users-<雜湊>`），`users.txt` 的內容（包括密碼和註解）一有變動，就會自動重建 Pod。所有桌面都在同一個 Pod 裡，所以重建時使用中的連線都會中斷。
- `users.txt` 含明文密碼，請不要提交到公開的 repo；可以改用 SOPS、Sealed Secrets 等工具管理。

### stateful 的 StorageClass

StorageClass 是決定 PVC 用哪種儲存的叢集設定。PVC 沒有指定 `storageClassName`，會使用叢集預設的 StorageClass，所以叢集一定要有一個預設的；先用 `kubectl get storageclass` 確認有沒有標著 `(default)` 的，沒有的話 PVC 會一直 `Pending`。

這個 StorageClass 必須是網路儲存，或設定成 `volumeBindingMode: WaitForFirstConsumer`，原因見 [ops/2026-10-28-tk8s-local-path-sc.md](ops/2026-10-28-tk8s-local-path-sc.md)。`local-path` 的 volume 只存在一台節點上，那台節點故障時 Pod 就起不來。

### 其他設定

- **換映像檔**（例如私有 registry 或 `-firefox` 版）：在 overlay 的 `kustomization.yaml` 加上 `images:` 區塊：

  ```yaml
  images:
  - name: ghcr.io/braveantony/rdp-vscode
    newTag: 1.0-firefox
  ```

- **改環境變數**：修改 `manifests/base/deployment.yaml` 的 `env`，再執行一次 `kubectl apply -k`。變數說明見 [README 的「環境變數」](../README.md#環境變數)。
- **自訂完整的 SSH 設定**（例如多個 Host）：參考 `manifests/example/ssh-configmap`。這個範例用 ConfigMap 整份取代由 `SSH_*` 產生的 SSH 設定；ConfigMap 裡一定要有名稱等於 `SSH_HOST_ALIAS` 的 `Host`，登入時才連得上。它以 `manifests/stateless` 為基礎，所以帳號清單是 `manifests/stateless/users.txt`。

## 單機（podman）

沒有 Kubernetes 時，可以在一台 Linux 主機上用 podman（類似 Docker 的容器工具）直接執行。單機沒有叢集，連不到預設的 tkadm，所以要用 `SSH_HOST` 等變數另外指定一台 SSH 主機。這台 SSH 主機需要：

- sshd 也要像 tkadm 一樣允許埠轉發（`AllowTcpForwarding local` 或 `yes`）
- 允許用密碼登入 SSH（container 裡沒有 SSH 金鑰）
- 能連到 `github.com`，因為第一次連線時會下載 vscodium-server

先把 `<SSH 主機>`、`<SSH 帳號>` 連同尖括號換成實際的值（例如 `192.168.1.10`、`alice`），再貼上。要連執行 podman 的這台主機本身時，`<SSH 主機>` 要填它的區網 IP，不能填 `localhost`，因為在 container 裡的 `localhost` 是 container 自己。

```bash
podman run -d --name rdp-vscode -p 13390:3389 --shm-size 1g \
  -e RDP_PASSWORD=bigred -e SSH_HOST=<SSH 主機> -e SSH_PORT=22 -e SSH_USER=<SSH 帳號> \
  ghcr.io/braveantony/rdp-vscode:1.0
```

用遠端桌面連到 `<主機 IP>:13390`。`<主機 IP>` 是執行 podman 的那台主機的 IP；在同一台主機上連可以用 `localhost:13390`。帳號 `bigred`、密碼 `bigred`。

要注意有兩組密碼：`RDP_PASSWORD` 是遠端桌面的登入密碼，可以自己改；登入後 VSCodium 會再問 `<SSH 帳號>` 在 SSH 主機上的密碼。

- `--shm-size 1g` 用來加大共用記憶體，因為用預設的 64 MiB 時，VSCodium 載入中文字型會崩潰。
- **多個帳號**：用帳號清單取代 `RDP_PASSWORD`。拿掉 `-e RDP_PASSWORD=bigred`，改在映像檔名稱之前加上 `-v ./users.txt:/etc/rdp-vscode/users:ro,Z`（`ro` 表示唯讀，`Z` 是給 SELinux 系統用的標記，沒有 SELinux 也不影響）。`users.txt` 的格式和[帳號清單](#帳號清單)相同。
- **不自動連線**：把 `-e SSH_HOST=…`、`-e SSH_PORT=…`、`-e SSH_USER=…` 都換成 `-e SSH_HOST_ALIAS=`（空字串），登入後只開啟 container 裡的 VSCodium，不會連到任何 SSH 主機。
- **SSH 主機上的家目錄不是 `/home/<SSH 帳號>` 時**（例如 root），再加上 `-e SSH_REMOTE_FOLDER=<路徑>`。
- **改裝 `-firefox` 版**：把最後的 `:1.0` 換成 `:1.0-firefox`。
- 檔案和設定都在 container 裡，刪掉 container（`podman rm -f rdp-vscode`）就會消失。
- 其他環境變數見 [README 的「環境變數」](../README.md#環境變數)。

## 從區網連線（節點在內部網段時）

如果節點位在某台 Linux 主機的內部網段（例如 tk8s，節點都是主機上的 podman container），區網裡的電腦連不到 NodePort。這時在那台主機上用 socat（把一個埠的連線轉送到另一個位址的小工具），把主機的 3390 埠轉到任一節點的 30390。

在那台主機上執行（需要 podman）；`<節點 IP>` 換成 `kubectl get nodes -o wide` 的 INTERNAL-IP 欄裡任一個：

```bash
podman run -d --name rdp-vscode-forward --restart=always --network host \
  docker.io/alpine/socat:1.8.0.3 TCP-LISTEN:3390,fork,reuseaddr TCP:<節點 IP>:30390
```

之後用遠端桌面連到 `<主機 IP>:3390`。

如果你是以一般使用者（不是 root）執行 podman，要讓這個 container 在你登出或主機重開機後仍然自動啟動，請再執行一次下面兩行：

```bash
sudo loginctl enable-linger $USER
systemctl --user enable podman-restart.service
```

## 移除

| 安裝方式 | 指令 |
|---|---|
| 快速安裝、Kustomize | `kubectl delete namespace rdp-vscode` |
| 單機 | `podman rm -f rdp-vscode` |
| 區網轉發 | `podman rm -f rdp-vscode-forward` |

stateful 模式的 PVC 會跟著 namespace 一起刪除。大多數 StorageClass 預設的 reclaimPolicy 是 `Delete`，這時 `/home` 的資料也會消失，要保留資料請先備份。

> 本文件的指令已於 2026-10-28 實測：快速安裝（包括從 GitHub 下載 `install.sh`、用 `RDP_VSCODE_IMAGE` 改裝 `-firefox` 版）與 Kustomize（stateless、stateful）在 tk8s 上部署並以 RDP 登入；單機以 `RDP_PASSWORD` 啟動並連上 SSH 主機，也以掛載帳號清單的方式啟動、用其中一個帳號登入，開啟的是該帳號自己的 VSCodium；區網轉發以 `192.168.11.64:3390` 登入。
