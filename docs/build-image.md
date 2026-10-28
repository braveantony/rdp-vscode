# rdp-vscode 映像檔建置手冊

本文件從原始碼做出 `ghcr.io/braveantony/rdp-vscode:1.2` 和 `:1.2-firefox` 兩個 tag，跑過測試，載入 tk8s 的節點並部署，最後推到 ghcr.io。**由上到下依序複製每個指令區塊貼到終端機執行。** 需要在 repo 目錄執行的區塊，開頭都會 `cd ~/rdp-vscode`，中途換終端機也能接著貼。

## 這個映像檔做什麼

| 功能 | 做法 |
|---|---|
| RDP 伺服器 | xrdp 0.10.1 + xorgxrdp：sesman 替每次登入啟動一個獨立的 Xorg，解析度跟著用戶端視窗 |
| 編輯器 | VSCodium 1.143.17183（固定版本），由 openbox 撐滿整個畫面、沒有邊框；關掉 VSCodium 就登出 |
| 自動連線 | 預裝 Open Remote-SSH 0.5.1，登入後自動以 SSH 連到 `tkadm`；遠端第一次連線時自動安裝 `redhat.vscode-yaml` |
| 中文介面 | 預裝繁體中文語言包 1.131.0，`VSCODIUM_LOCALE` 切換 `zh-tw` 或 `en` |
| 字型 | 預裝 Cascadia Code 和 JetBrains Mono，`VSCODIUM_FONT` 選擇編輯器和終端機的預設字型；中文用 Noto Sans Mono CJK TC |
| 多人同時使用 | sesman `Policy=Separate`：每次登入都有自己的桌面和 VSCodium 資料目錄（`/tmp/sess/<display>.<uid>`），同一個帳號的設定透過 symlink 共用 |
| 安全 | 帳密在啟動時由 Secret 設定，不寫進映像檔；每個 Pod 自己產生 TLS 憑證和 RSA 金鑰 |

## 前置需求

| 項目 | 需求 |
|---|---|
| 建置工具 | podman |
| 網路 | 建置時要能連到 `deb.debian.org`、`github.com`（VSCodium）、`open-vsx.org`（擴充功能） |
| 磁碟 | 至少 5 GB 可用空間（兩個 tag 約 1.3 GB 和 1.6 GB，大部分 layer 共用） |
| CPU 架構 | x86_64 |
| 測試 | `bash`、`nc`、`python3`（含 PyYAML）、`kubectl`；載入 tk8s 節點需要 `sudo` |

```bash
podman --version
df -h ~
```

> **注意**：如果建置的這台主機同時跑著 K8s 節點（例如 tk8s 的節點 container 共用主機磁碟），磁碟使用率超過 85% 時，kubelet 會開始刪除節點上沒在用的映像檔。建置前請確認建置後仍低於 85%。

## Step 1：取得原始碼

```bash
git clone https://github.com/braveantony/rdp-vscode.git ~/rdp-vscode
cd ~/rdp-vscode
ls
```

主要檔案：

```text
rdp-vscode/
├── VERSION                        # 目前版本
├── install.sh                     # 快速開始的 curl | bash 安裝腳本
├── images/rdp-vscode/
│   ├── Dockerfile                 # 版本號在開頭的 ARG
│   ├── rootfs/                    # 整個目錄 COPY 到映像檔的 /
│   │   ├── etc/xrdp/startwm.sh    # 每個桌面的啟動和清理
│   │   ├── etc/skel/.config/      # 新 home 的 openbox 和 VSCodium 預設設定
│   │   └── opt/rdp-vscode/        # entrypoint、帳號、SSH 設定、擴充功能同步
│   └── rootfs-firefox/            # 只有 WITH_FIREFOX=1 才會用到
├── manifests/                     # Kustomize：base、stateless、stateful、example
├── docs/                          # 本文件、架構、使用手冊、設計文件
└── test/                          # unit、image、deploy、e2e 測試
```

## Step 2：建置兩個 tag

```bash
cd ~/rdp-vscode
podman build -t ghcr.io/braveantony/rdp-vscode:1.2 images/rdp-vscode
podman build --build-arg WITH_FIREFOX=1 -t ghcr.io/braveantony/rdp-vscode:1.2-firefox images/rdp-vscode
podman image ls ghcr.io/braveantony/rdp-vscode
```

兩個 tag 只有最後一層不同（`WITH_FIREFOX=1` 才安裝 Firefox ESR），所以第二次建置只要幾分鐘。建置時會檢查 GitHub 上有沒有對應版本的 `vscodium-reh-alpine-x64`（`tkadm` 是 Alpine，Open Remote-SSH 會在上面安裝這個 server），找不到就讓建置失敗。

## Step 3：測試

不需要叢集的測試：

```bash
cd ~/rdp-vscode
bash test/unit/ssh-config.test.sh
bash test/unit/font-config.test.sh
bash test/unit/install.test.sh
bash test/unit/startwm.test.sh ghcr.io/braveantony/rdp-vscode:1.2
bash test/image/smoke.test.sh ghcr.io/braveantony/rdp-vscode:1.2
bash test/image/smoke.test.sh ghcr.io/braveantony/rdp-vscode:1.2-firefox --firefox
bash test/unit/accounts.test.sh ghcr.io/braveantony/rdp-vscode:1.2
bash test/unit/languagepacks.test.sh ghcr.io/braveantony/rdp-vscode:1.2
```

每個測試最後一行都應該是 `N passed, 0 failed`。

以下兩個測試要連到 tk8s：`session.test.sh` 用 tk8s 的 CoreDNS（`10.98.0.10`）解析 `tkadm.taroko`；`render.test.sh` 會對叢集做 server 端的 dry run，不會建立任何資源。

```bash
cd ~/rdp-vscode
bash test/image/session.test.sh ghcr.io/braveantony/rdp-vscode:1.2
bash test/deploy/render.test.sh
```

`session.test.sh` 會用 FreeRDP 實際登入，約需 5 分鐘，截圖存在 `test/e2e/out/`。

## Step 4：載入 tk8s 的節點

tk8s 的節點是 podman container，映像檔要直接載入節點的 container 儲存區。`imagePullPolicy` 是 `IfNotPresent`，節點上已經有這個 tag，就不會去 ghcr.io 拉。

```bash
cd ~/rdp-vscode
podman save -o /tmp/rdp-vscode.tar ghcr.io/braveantony/rdp-vscode:1.2
for n in tk8s-control-plane-1 tk8s-worker-1 tk8s-worker-2; do
  sudo podman --root /var/lib/containers/storage/volumes/$n-var/_data/lib/containers/storage \
    --runroot /run/rdp-vscode-load-$n --storage-driver overlay load -i /tmp/rdp-vscode.tar
done
rm -f /tmp/rdp-vscode.tar
```

要用 `-firefox` 版時，把上面的 `:1.2` 換成 `:1.2-firefox`，並在 overlay 的 `kustomization.yaml` 加上 `images:` 區塊換成 `newTag: 1.2-firefox`（見[安裝手冊](install.md#其他設定)）。

## Step 5：tk8s 的前置設定

這兩項只要做一次。

**`tkadm` 的 sshd 要允許本機埠轉發。** tkadm 是 Alpine，openssh 預設 `AllowTcpForwarding no`，Open Remote-SSH 會連不上。修改方式和紀錄見 [ops/2026-10-27-tkadm-sshd-forwarding.md](ops/2026-10-27-tkadm-sshd-forwarding.md)。確認：

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- /usr/sbin/sshd -T | grep allowtcpforwarding
```

應該顯示 `allowtcpforwarding local`（或 `yes`）。

**stateful 模式需要 `WaitForFirstConsumer` 的 StorageClass。** 只用 stateless 模式可以跳過。確認：

```bash
kubectl get sc local-path -o jsonpath='{.volumeBindingMode}{"\n"}'
```

應該顯示 `WaitForFirstConsumer`。如果是 `Immediate`，修改方式和紀錄見 [ops/2026-10-28-tk8s-local-path-sc.md](ops/2026-10-28-tk8s-local-path-sc.md)。

## Step 6：部署並從區網連線

```bash
cd ~/rdp-vscode
kubectl apply -k manifests/stateless
kubectl -n rdp-vscode rollout status deploy/rdp-vscode
kubectl -n rdp-vscode get pod -o wide
```

tk8s 的節點在主機內部的網段，區網裡的 Windows 連不到 NodePort，所以在主機上做埠轉發（`172.22.0.2` 是 tk8s-worker-1；原理和開機後自動啟動的設定見[安裝手冊的「從區網連線」](install.md#從區網連線節點在內部網段時)）：

```bash
podman run -d --name rdp-vscode-forward --restart=always --network host \
  docker.io/alpine/socat:1.8.0.3 TCP-LISTEN:3390,fork,reuseaddr TCP:172.22.0.2:30390
```

Windows「遠端桌面連線」填 `<主機 IP>:3390`（例如 `192.168.11.64:3390`），接下來的操作見[使用手冊](user-guide.md)。

開網站時，可以用短名稱 `http://<service>.<namespace>`，也可以用完整網域名稱 `http://<service>.<namespace>.svc.<cluster domain>`。叢集的 cluster domain 可以這樣查（tk8s 是 `tk8s.k8s`）：

```bash
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep kubernetes
```

## Step 7：推到 ghcr.io

需要一個有 `write:packages` 權限的 GitHub Personal Access Token（PAT）。

```bash
podman login ghcr.io -u braveantony      # 密碼貼上 PAT
podman push ghcr.io/braveantony/rdp-vscode:1.2
podman push ghcr.io/braveantony/rdp-vscode:1.2-firefox
```

Dockerfile 裡的 `org.opencontainers.image.source` label 會讓 ghcr.io 自動把 package 連到 repo。第一次推送後，到 GitHub 的 **Packages → rdp-vscode → Package settings → Change visibility**，設為 Public，別人才拉得到。

## 完整驗收（e2e，選用）

stateless 用 checkout 裡的 `install.sh` 部署、stateful 用 Kustomize 部署，各自登入並逐項檢查：

```bash
cd ~/rdp-vscode
bash test/e2e/run.sh all
```

約需 25 分鐘。執行前要知道：

- `run.sh` 會自己建置 `localhost/rdp-vscode:dev` 並載入節點，用它**重新部署** namespace `rdp-vscode`，所以會蓋掉 Step 6 的部署。
- 結束時會**刪除整個 namespace `rdp-vscode`**，也會刪除 namespace `default` 裡的 `web`（測試用的 nginx）。要保留部署，設 `E2E_KEEP=1`。
- 執行完要再做一次 Step 6 的部署。不要在正式使用中的叢集上執行。

只能用眼睛確認的項目列在 [test/e2e/manual-checklist.md](../test/e2e/manual-checklist.md)。

## 升級 VSCodium

版本號都在 `images/rdp-vscode/Dockerfile` 開頭：

```dockerfile
ARG VSCODIUM_VERSION=1.143.17183
ARG OPEN_REMOTE_SSH_VERSION=0.5.1
ARG ZH_HANT_VERSION=1.131.0
```

1. 在 [VSCodium releases](https://github.com/VSCodium/vscodium/releases) 挑新版本，確認同一個 release 裡同時有 `codium_<版本>_amd64.deb` 和 `vscodium-reh-alpine-x64-<版本>.tar.gz`：

   ```bash
   V=1.143.17183      # 換成新版本
   for f in codium_${V}_amd64.deb vscodium-reh-alpine-x64-${V}.tar.gz; do
     curl -fsSIL -o /dev/null https://github.com/VSCodium/vscodium/releases/download/$V/$f && echo "OK $f"
   done
   ```

2. 確認語言包的 `engines.vscode` 涵蓋新版本。到 [Open VSX 的語言包頁面](https://open-vsx.org/extension/MS-CEINTL/vscode-language-pack-zh-hant) 看最新版，或：

   ```bash
   curl -fsSL https://open-vsx.org/api/MS-CEINTL/vscode-language-pack-zh-hant | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["engines"])'
   ```

3. 修改 `images/rdp-vscode/Dockerfile` 的 `ARG`，從 Step 2 重做一次，並跑完 Step 3 的所有測試和完整驗收。新 tag 用新的版本號：把 Step 2～4、7 指令裡的 `:1.2` 和 `:1.2-firefox` 分別換成例如 `:1.3` 和 `:1.3-firefox`，並同步修改 `VERSION` 和 `manifests/base/deployment.yaml` 的 `image:`。注意：Step 3 測的是指定的發佈 tag；完整驗收則是從目前的原始碼另外建置 `localhost/rdp-vscode:dev` 來測。

使用者的 home 裡如果有舊版的預裝擴充功能，下次登入時會自動換成映像檔裡的版本；自己裝的擴充功能不會被動到。

## 附錄：已知行為與建置時踩過的坑

| 現象 | 原因與處理 |
|---|---|
| 登入後 VSCodium 一閃就消失，桌面隨即結束 | `/dev/shm` 太小。Chromium 會把中文字型放進共用記憶體，預設 64 MB 不夠，log 會出現 `font_data_service ... No space left on device`。K8s 部署已掛 1 GiB 的記憶體 `emptyDir`；用 podman 直接執行時要加 `--shm-size=1g` |
| `VSCODIUM_LOCALE=zh-tw` 但介面是英文 | VSCodium 第一次啟動後才產生 `languagepacks.json`，下次啟動才套用語言。每個桌面都用全新的資料目錄，所以 `startwm.sh` 在啟動前先用 `languagepacks.js` 產生這個檔案 |
| container 的環境變數在 VSCodium 裡讀不到 | sesman 用乾淨的環境啟動桌面。entrypoint 把 `VSCODIUM_LOCALE`、`SSH_HOST_ALIAS`、`SSH_REMOTE_FOLDER` 寫到 `/run/rdp-vscode/session.env`，由 `startwm.sh` 讀取 |
| `codium` 啟動後馬上返回 | `/usr/bin/codium` 是啟動器，會把主程式丟到背景後立刻結束。`startwm.sh` 直接執行 `/usr/share/codium/codium`，關掉視窗時才返回 |
| Open Remote-SSH 一直重新連線、每次都問密碼 | SSH 目標的 sshd 是 `AllowTcpForwarding no`。改成 `local`，見 Step 5 |
| 在 ssh 設定加了 `ControlMaster` 沒有效果 | Open Remote-SSH 用內建的 SSH 實作，不呼叫系統的 `ssh`；它會讀 `Host`、`HostName`、`Port` 這些基本設定，但不支援 `ControlMaster` |
| `codium --version` 在映像檔裡印出 super user 警告 | VSCodium 拒絕以 root 執行；測試時要用一般使用者（例如 `--user 65534`） |

> 本文件的指令已於 2026-10-28 在 tk8s 上照貼實測：Step 2 建置兩個 tag、Step 3 的所有測試、Step 4 載入三個節點、Step 5 的兩項檢查、Step 6 部署 stateless 並啟動 socat 轉發，再用 FreeRDP 連 `192.168.11.64:3390` 登入、輸入 tkadm 密碼後連線成功；完整驗收 `test/e2e/run.sh all` 22 項通過；「升級 VSCodium」的兩個查詢指令。Step 1 的 `git clone`（repo 尚未公開）、Step 7 的推送，以及 Windows 實機連線尚未實測。
