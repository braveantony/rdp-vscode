# rdp-vscode 架構圖

架構的文字說明見 [../architecture.md](../architecture.md)。這個目錄放的是架構圖本身與產圖腳本。

- `rdp-vscode-architecture.png`：2480 × 1960 PNG。
- `rdp-vscode-architecture.svg`：可編輯的 SVG，文字使用繁體中文。
- `render.py`：產生上述兩個檔案的原始碼；只需要 Python 3 標準函式庫、系統的 libfreetype 與中文字型。

重製方式：在 repo 根目錄執行（會覆寫這個目錄裡的 PNG 和 SVG）。主機沒有中文字型時，在 alpine container 裡執行：

```sh
podman run --rm -v "$PWD:/w:Z" -w /w docker.io/library/alpine:3.22 sh -c \
  'apk add -q --no-cache python3 freetype font-wqy-zenhei >/dev/null &&
   python3 docs/architecture/render.py /usr/share/fonts/wqy-zenhei/wqy-zenhei.ttc'
```

PNG 使用 WenQuanYi Zen Hei（文泉驛正黑）字型，檢視時不需要另外安裝字型。SVG 在檢視端需要安裝文泉驛正黑或 Noto Sans CJK TC。

核對來源：`manifests/base/{deployment,service,kustomization}.yaml`、`manifests/{stateless,stateful}/`、`images/rdp-vscode/Dockerfile`、`rootfs/opt/rdp-vscode/entrypoint.sh`、`rootfs/opt/rdp-vscode/ssh-config.sh`、`rootfs/etc/xrdp/startwm.sh`（rootfs 路徑相對於 `images/rdp-vscode`），以及 [docs/spike-notes.md](../spike-notes.md) 的 Open Remote-SSH 驗證結果。

## 圖面說明

- 圖中的 Pod 由 Deployment `rdp-vscode` 管理，實際的 Pod 名稱會加上隨機後綴。
- Service 位於 namespace `rdp-vscode`。圖中的連線表示 NodePort 的轉送關係，Service 並不是一個獨立執行的代理程式。
- `rdp-vscode` 與 `taroko` 兩個 namespace 各畫成一個完整的矩形。`tkadm.taroko` 是預設的 SSH 目標，本 repo 不提供 tkadm 的部署清單。Kubernetes API 不屬於任何一個 namespace，畫在兩者之外。
- Secret 名稱由 overlay 加上內容雜湊；ConfigMap `rdp-vscode-ssh` 是選用的，沒有掛載時 SSH 設定由 `SSH_*` 環境變數產生。
- 粗藍線是從用戶端經 RDP 進入 VSCodium 桌面的主路徑。VSCodium 方塊畫在 Xorg session 裡，表示 VSCodium 在該桌面內全螢幕執行。
- 綠線是 VSCodium 到 tkadm 的 SSH 連線；連上後經 sshd 的本機埠轉發連到 ③ vscodium-server，所以 tkadm 的 sshd 必須是 `AllowTcpForwarding local`。
- 橙線：VSCodium 的 Integrated Browser 直接開叢集內的 Web 服務；tkadm 上的 kubectl 呼叫 Kubernetes API。
- Pod 內只有一個 `desktop` container（虛線框），映像檔為 `ghcr.io/braveantony/rdp-vscode:1.2`。方塊右上角的標籤標明種類：`process`／`processes` 表示一個或多個執行中的程式（① 是 xrdp 和 xrdp-sesman 兩個）；`session` 表示一組 process 組成的桌面（②）；`volume` 是掛載的儲存空間。這些都不是額外的 container。
  - ① 由 tini 與 `/opt/rdp-vscode/entrypoint.sh` 在 container 啟動時開啟。
  - ② 在使用者登入時，由 xrdp-sesman 透過 `startwm.sh` 開啟。
- ③ vscodium-server 在 tkadm 上執行，由 Open Remote-SSH 在每次連線時啟動（tkadm 上還沒有這個版本時，會先下載），不屬於 rdp-vscode Pod。
