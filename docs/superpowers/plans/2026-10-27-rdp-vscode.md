# rdp-vscode 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者用 RDP 連進 K8s 裡的 pod，畫面就是全螢幕 VSCodium，並自動透過 Open Remote-SSH 連到叢集內的 `tkadm` pod（bigred/bigred）。

**Architecture:** 以 `~/rdp-firefox/v3-rdp`（Alpine + xrdp + xorgxrdp + openbox kiosk、users.txt 多帳號、kustomize）為範本，改用 `debian:trixie-slim` 並把 Firefox 換成固定版本的 VSCodium。SSH Host 由 entrypoint 依環境變數或 ConfigMap 產生到 `/etc/ssh/ssh_config.d/`。部署以 kustomize 分成 stateless 與 stateful 兩個 overlay。

**Tech Stack:** Debian trixie、xrdp 0.10 + xorgxrdp、openbox、VSCodium（固定版本 `.deb`）、Open VSX 擴充（`jeanp413.open-remote-ssh`、`MS-CEINTL.vscode-language-pack-zh-hant`、`redhat.vscode-yaml`）、tini、bash、podman、kustomize、FreeRDP（e2e 測試用）。

**Spec:** 本檔第 1 部分（設計決策）就是 spec，計畫和 spec 放在同一個檔案裡。

---

## 第 1 部分：設計決策（Spec）

### 1.1 產品與授權

| # | 項目 | 決定 |
|---|---|---|
| D1 | 定位 | Open source，不做商業用途 |
| D2 | 編輯器 | **VSCodium** + **Open Remote-SSH**（`jeanp413.open-remote-ssh`），不使用 Microsoft 官方 VS Code 和 Remote-SSH（兩者授權都不允許重新散佈） |
| D14 | 名稱與授權 | GitHub repo：`braveantony/rdp-vscode`；image：`ghcr.io/braveantony/rdp-vscode:1.0`、`:1.0-firefox`；授權：**Apache-2.0** |
| D15 | Build | 用 podman 手動 build、手動 push，不做 CI |
| D16 | 版本 | `ARG VSCODIUM_VERSION` 固定版本，build 時驗證 GitHub release 上有對應的 `vscodium-reh-alpine-x64-<ver>.tar.gz`；image 裡預裝的 `.vsix`（Open Remote-SSH、繁中語言包）也固定版本；遠端自動安裝的 `redhat.vscode-yaml` 不固定版本，一律裝 Open VSX 上的最新版 |

### 1.2 Image 內容與執行行為

| # | 項目 | 決定 |
|---|---|---|
| D2 | Base image | `debian:trixie-slim`（VSCodium 是 glibc 程式，不能用 Alpine） |
| D3 | 多使用者 | 一個 pod 多個帳號，帳號來自 `users.txt`（Secret）或 `RDP_USER`/`RDP_PASSWORD`；每條連線各自一個 Xorg（`Policy=Separate`）；預設帳號 bigred/bigred |
| D6 | 畫面 | openbox kiosk 模式，只有 VSCodium（最大化、無邊框）；**關掉 VSCodium 就登出**；啟動時自動開一個 `ssh-remote+tkadm` 視窗，跳出密碼框 |
| D7 | 瀏覽器 | 內建 Simple Browser，在 pod 內直接解析 Service 名稱（完整 FQDN `<svc>.<ns>.svc.<cluster-domain>`，或靠 search domain 的短名稱 `<svc>.<ns>`），不需要 port forwarding |
| D8 | Firefox | build arg `WITH_FIREFOX=1` 產生 `-firefox` tag：裝 `firefox-esr`，並設為 `xdg-open` 的預設瀏覽器；預設 image 不含 Firefox |
| D9 | Session 分享 | 第一版不做；optional 功能的 layer 放在 Dockerfile 最後面，方便以後加 |
| D17 | 語系 | 預設繁中（`VSCODIUM_LOCALE=zh-tw`），設 `VSCODIUM_LOCALE=en` 切成英文；語言包一律預裝；`LANG=zh_TW.UTF-8`、`TZ=Asia/Taipei`；字型用 Noto CJK；中文透過 RDP 剪貼簿貼上，不裝輸入法 |
| D18 | Extension | 本地預裝 Open Remote-SSH 和繁中語言包；遠端（tkadm）只自動裝 `redhat.vscode-yaml`，並開啟 Kubernetes schema |
| B5 | 預裝 extension 的版本同步 | 預裝的 `.vsix` 解壓到 `/opt/rdp-vscode/extensions`（**不放 skel**）。每次 session 啟動時，startwm.sh 把使用者 `~/.vscode-oss/extensions` 裡的預裝 extension 同步成 image 的版本（版本不同就換掉）；使用者自己裝的 extension 不動。這樣 stateful 模式升級 image 後，Open Remote-SSH 和語言包也會跟著 VSCodium 一起升級 |
| B3 | 本地 terminal | 允許使用（`Terminal: Create New Integrated Terminal (Local)` 會在 rdp-vscode pod 裡以自己的 RDP 帳號執行），做基本隔離：`/home/<user>` 權限 `0700`，帳號不給 sudo |
| A1 | 拿掉的功能 | 不沿用 rdp-firefox 的 ttyd web terminal（2200/2210）、`myssh`、`term.sh` |
| A2 | 安全 | xrdp 在容器啟動時自己產生 TLS 憑證和 RSA 金鑰；listener 降權為 `xrdp`；密碼不寫進 image；`AllowRootLogin=false` |
| A3 | Electron sandbox | 容器裡以非 root 執行；如果 Task 0 驗證 sandbox 跑不起來，就加 `--no-sandbox` |

### 1.3 SSH 連線

| # | 項目 | 決定 |
|---|---|---|
| D4 | 認證 | ssh_config 只寫 Host 設定，**連線時在 VSCodium 跳出的密碼框輸入密碼**；不使用金鑰，也不修改 tkadm |
| D5 | 目標設定 | 用環境變數產生，有 ConfigMap 時以 ConfigMap 為準（見下表）；寫到 `/etc/ssh/ssh_config.d/rdp-vscode.conf`，每次啟動都重新產生；不修改使用者的 `~/.ssh/config` |
| D11a | Host key | `StrictHostKeyChecking accept-new`、`UserKnownHostsFile /dev/null`、`LogLevel ERROR` |
| B4 | 連線共用 | env 產生的 Host 加上 `ControlMaster auto`、`ControlPath /tmp/ssh-cm-%i-%C`、`ControlPersist 30m`：輸入一次密碼後，30 分鐘內的重連和同帳號的第二個 session 都不用再輸入。ConfigMap 自訂的設定不自動加。如果 Task 0 驗證 Open Remote-SSH 不相容，就拿掉這三行 |
| B1 | 遠端帳號 | 所有 RDP 帳號都以 tkadm 上的 **bigred** 身分登入（共用 home、`~/.vscodium-server` 和 kubeconfig）。README 要註明這點：需要學生彼此隔離時，應該一人部署一套 rdp-vscode 加 tkadm |
| — | tkadm 那一側 | 完全不修改。`~/.vscodium-server` 在 tkadm 重啟後會重新下載（約 60MB）；README 要說明這點 |

環境變數（預設值）：

| 變數 | 預設值 | 用途 |
|---|---|---|
| `SSH_HOST_ALIAS` | `tkadm` | ssh_config 的 `Host` 名稱，也是自動連線的目標；設成空字串就不自動連線 |
| `SSH_HOST` | `tkadm.taroko`（短名稱，靠 pod 的 search domain 解析，不受 cluster domain 影響；tk8s 的 cluster domain 是 `tk8s.k8s`，**不是** `cluster.local`） | `HostName` |
| `SSH_PORT` | `22100` | `Port` |
| `SSH_USER` | `bigred` | `User` |
| `SSH_REMOTE_FOLDER` | `/home/$SSH_USER` | 自動連線後要開啟的遠端資料夾 |
| `VSCODIUM_LOCALE` | `zh-tw` | VSCodium 的 `--locale` |
| `MAX_SESSIONS` | `3` | sesman `MaxSessions` |
| ConfigMap 掛載點 | `/etc/rdp-vscode/ssh/config` | 檔案存在且不是空的，就整份取代環境變數產生的設定 |

### 1.4 部署

| # | 項目 | 決定 |
|---|---|---|
| D10 | 位置 | namespace **`rdp-vscode`**，Service 用 NodePort **`30390`** |
| D11 | Overlay | `deploy/stateless`（`/home` 用 emptyDir）、`deploy/stateful`（`/home` 用 PVC） |
| D12 | Stateful | 一個 PVC（5Gi，RWO，**不指定 `storageClassName`，使用叢集預設的 SC**）掛 `/home`；Deployment `replicas: 1`、`strategy: Recreate`；home 只在不存在時才從 `/etc/skel` 建立 |
| B2 | 儲存前提 | 預設 SC 必須是 `WaitForFirstConsumer`（例如 local-path）或網路儲存；README 要註明，並說明 local-path 綁定節點的限制。**tk8s 前置作業**：目前 `local-path` SC 是 `Immediate`，provisioner 會回報 `no node was specified`（vault 的 3 個 PVC 因此 Pending 了 7 天），必須重建成 `WaitForFirstConsumer`。這會改到叢集設定，**執行前要先經使用者同意** |
| B6 | 預設帳密警告 | 維持 bigred/bigred 作為預設值；README 開頭加上明顯的警告：預設帳密只適合隔離的實驗環境，而且這條權限鏈（RDP → 叢集內網路 → tkadm → kubectl）等於擁有整個叢集的控制權。`users.txt` 開頭也加註解提醒要修改。**entrypoint 不加警告** |
| — | Image 參照 | manifest 預設用 `ghcr.io/braveantony/rdp-vscode:1.0` 搭配 `imagePullPolicy: IfNotPresent`；e2e 測試用 kustomize `images:` 換成 `localhost/rdp-vscode:dev`；image 預估約 1.2GB |
| D13 | 資源 | requests `cpu: 500m, memory: 1Gi`；limits `cpu: 4, memory: 4Gi`（以 3 人同時連線估算，每多一人約加 1Gi）；`/dev/shm` 用 `emptyDir{medium: Memory, sizeLimit: 1Gi}` |
| — | 帳號 Secret | `rdp-vscode-users`（key `users`），由 overlay 的 secretGenerator 產生，預設內容是 `bigred:bigred`；掛載到 `/etc/rdp-vscode/users` |

### 1.5 文件

| # | 項目 | 決定 |
|---|---|---|
| D19 | 文件 | `README.md`（英文）、`README.zh-TW.md`（繁中），兩者互相連結；`build-image.md`、`user-guide.md` 用繁中；程式碼註解和 commit message 用英文 |

### 1.6 驗收標準（D20）

| # | 驗收項目 | 驗證方式 |
|---|---|---|
| AC1 | `kubectl apply -k deploy/stateless` 後，pod 會 Ready | 自動 |
| AC2 | 用 RDP 連 `<節點 IP>:30390`，以 bigred/bigred 登入 | 自動（FreeRDP） |
| AC3 | 畫面是全螢幕 VSCodium，自動跳出 tkadm 密碼框；輸入 `bigred` 後左下角顯示 `SSH: tkadm` | 自動（xdotool + 截圖）＋手動確認 |
| AC4 | 在 VSCodium terminal（tkadm 上）執行 `kubectl create deploy web --image=nginx && kubectl expose deploy web --port 80` | 自動（`kubectl` 檢查）＋手動 |
| AC5 | 用 Simple Browser 打開 `http://web.default.svc.tk8s.k8s`（tk8s 的完整 FQDN），看到 nginx 歡迎頁 | 手動；自動部分：在 pod 內 `curl` 該 FQDN 會回傳 200 |
| AC6 | YAML 檔有 Kubernetes schema 補全 | 手動；自動部分：tkadm 上 `~/.vscodium-server/extensions` 有 `redhat.vscode-yaml-*` |
| AC7 | 關掉 VSCodium，RDP session 跟著結束 | 自動 |
| AC8 | Stateful：改一個設定、刪掉 pod、重新連線後設定還在 | 自動 |
| AC9 | `-firefox` tag：點連結會開 Firefox，而且 Firefox 能用 FQDN 開網站 | 手動；自動部分：`xdg-settings get default-web-browser` 回傳 `firefox-esr.desktop` |
| AC10 | `VSCODIUM_LOCALE=en` 時介面是英文 | 自動（檢查 codium 程序參數）＋截圖 |

---

## 第 2 部分：實作計畫

### Global Constraints

- Base image：`debian:trixie-slim`；CPU 架構：x86_64
- 所有 shell 腳本用 `#!/bin/bash` 和 `set -eu`，註解和 log 訊息用英文，log 前綴用 `[entrypoint]` 或 `[session]`（跟 rdp-firefox 一致）
- 路徑：腳本放在 `/opt/rdp-vscode/`；預裝 extension 放在 `/opt/rdp-vscode/extensions/`；帳號 Secret 掛到 `/etc/rdp-vscode/users`；SSH ConfigMap 掛到 `/etc/rdp-vscode/ssh/config`；產生的 SSH 設定寫到 `/etc/ssh/ssh_config.d/rdp-vscode.conf`
- Namespace `rdp-vscode`；Deployment、Service、container 名稱都叫 `rdp-vscode`；container port 名稱 `rdp`（3389）；NodePort `30390`
- Image：`ghcr.io/braveantony/rdp-vscode:1.0`，Firefox 版本是 `:1.0-firefox`；本機測試 tag 用 `localhost/rdp-vscode:dev`、`localhost/rdp-vscode:dev-firefox`
- 保留帳號名稱：`root`、`xrdp`；帳號名稱規則：`^[a-z_][a-z0-9_-]{0,31}$`；UID 從 1000 開始
- 每個 session 的暫存目錄：`/tmp/sess/<display>.<uid>/`（沿用 rdp-firefox 的做法）
- 授權 Apache-2.0；commit message 用英文，結尾附上指定的 `Co-Authored-By` 和 `Claude-Session` 兩行
- 測試腳本建立的容器、volume 和 port-forward 一律用固定名稱，並用 `trap ... EXIT` 清除，測試中途失敗也要清乾淨，避免佔住 port（例如 33390）影響後面的 task
- 使用者面對的文件用繁中（`README.md` 用英文）

### Review Focus

1. **同一個帳號同時登入兩次**：兩條連線要各自有一個 VSCodium，不能因為 single-instance 機制把第二個視窗開到第一個人的畫面上。→ Task 4 的 `same-account-twice` 測試
2. **Stateful 時 users.txt 順序被調換**：UID 依照順序分配，換順序後 UID 會變。entrypoint 必須把已存在的 `/home/<user>` chown 給新的 UID，使用者才不會因為讀不到自己的 home 而登入失敗。→ Task 3 的 `uid-reorder` 測試
3. **ConfigMap 檔案存在但內容是空的**：要退回用環境變數產生，而不是寫出一個空設定，導致自動連線失敗。→ Task 1 的 `empty-configmap` 測試
4. **RDP 斷線但沒有關 VSCodium**：120 秒後 session 要被清掉，不能留下 Electron 程序繼續佔記憶體（3 個人的殘留程序就可能讓整個 pod 被 OOMKilled）。→ Task 4 的 `disconnect-cleanup` 測試
5. **tkadm 連不上或密碼打錯**：VSCodium 要顯示錯誤，但 session 不能因此登出或反覆重開；使用者要能從 Remote Explorer 再試一次。→ Task 7 的 e2e 測試，用 `SSH_HOST` 指向不存在的主機

---

### 檔案結構

```
rdp-vscode/
├── LICENSE                                   # Apache-2.0
├── README.md / README.zh-TW.md
├── build-image.md / user-guide.md
├── Dockerfile
├── rootfs/
│   ├── opt/rdp-vscode/
│   │   ├── entrypoint.sh        # accounts, homes, TLS, ssh config, start xrdp
│   │   ├── accounts.sh          # parse users file -> create/update accounts
│   │   ├── ssh-config.sh        # print ssh_config from env or ConfigMap
│   │   ├── sync-extensions.sh   # sync bundled extensions into user extensions dir
│   │   └── extensions/          # bundled extensions (from pinned .vsix, at build time)
│   ├── etc/xrdp/startwm.sh      # per-session: data dir, openbox, codium, logout on exit
│   └── etc/skel/
│       ├── .config/openbox/rc.xml              # kiosk + Alt-Tab
│       └── .config/VSCodium/User/settings.json # defaults (yaml schema, remote ext, update off)
├── rootfs-firefox/              # copied only when WITH_FIREFOX=1
│   └── etc/xdg/mimeapps.list
├── deploy/
│   ├── base/        {kustomization,namespace,deployment,service}.yaml
│   ├── stateless/   kustomization.yaml, users.txt, home-emptydir.yaml
│   ├── stateful/    kustomization.yaml, users.txt, pvc.yaml, home-pvc.yaml
│   └── example/     ssh-configmap/ (ssh_config ConfigMap overlay example)
├── tests/
│   ├── lib.sh                   # pass/bad/say helpers
│   ├── unit/ssh-config.test.sh
│   ├── unit/accounts.test.sh
│   ├── image/smoke.test.sh
│   ├── image/session.test.sh
│   ├── deploy/render.test.sh
│   └── e2e/{run.sh, client/Dockerfile, client/login.sh}
└── docs/spike-notes.md
```

---

### Task 0：技術驗證（Spike）

有幾個前提只能實際跑過才知道，而後面的 task 都依賴這些結果。這個 task 不產出正式程式碼，只產出 `docs/spike-notes.md` 和固定的版本號。

**Files:**
- Create: `docs/spike-notes.md`

**Interfaces:**
- Produces：`VSCODIUM_VERSION`、`OPEN_REMOTE_SSH_VERSION`、`ZH_HANT_VERSION` 三個版本號（`redhat.vscode-yaml` 只在 spike-notes 記錄驗證時的版本，不固定）；以及以下 8 個問題的結論，Task 2 和 Task 4 會直接採用

- [ ] **Step 1：選定版本。** 從 `https://api.github.com/repos/VSCodium/vscodium/releases/latest` 取得最新的 stable 版本，確認同一個 release 裡同時有 `codium_<ver>_amd64.deb` 和 `vscodium-reh-alpine-x64-<ver>.tar.gz`。兩個預裝 extension 從 `https://open-vsx.org/api/<publisher>/<name>` 取得最新版本，確認 Open Remote-SSH 支援這個 VSCodium 版本（看 `engines.vscode`）。
- [ ] **Step 2：做一個拋棄式容器**（`debian:trixie-slim` 加上 xrdp、xorgxrdp、openbox，再裝上面那版 `.deb`），用 `localhost/rdp-firefox-e2e-client` 連進去，逐一回答下面的問題，把結論記錄到 `docs/spike-notes.md`：
  1. 非 root 使用者啟動 `/usr/share/codium/codium` 時，需不需要 `--no-sandbox`？
  2. 用 `<codium binary> ... & wait $!` 的方式（沿用 rdp-firefox）啟動 Electron binary（加上 `--user-data-dir <dir> --remote ssh-remote+tkadm <folder>`），程序會不會一直存活到視窗關閉，讓 `wait` 在關閉時才返回？（startwm.sh 靠這個行為做「關掉就登出」）如果 binary 會 fork 後立刻結束，要改用什麼參數，例如 `--wait`？另外確認：sesman 結束 session 時，startwm.sh 會不會收到 SIGTERM，讓 `wait` 中斷、trap 執行清理
  3. Open Remote-SSH 連到 tkadm（Alpine、port 22100）時，是否會跳出密碼框，並成功下載 `reh-alpine-x64`？需要哪些設定，例如 `remote.SSH.serverDownloadUrlTemplate`？
  4. 要讓 `redhat.vscode-yaml` 自動裝到遠端，Open Remote-SSH 支援哪個設定（`remote.SSH.defaultExtensions` 或其他）？如果都不支援，備案是什麼？
  5. `workbench.externalUriOpeners` 能不能用 不綁定 cluster domain 的 pattern（例如 `*.svc.*`、`*.svc.*:*`） 這種 pattern，讓叢集內網址預設用 Simple Browser 開啟？
  6. 用 `--user-data-dir` 為每個 session 指定獨立的資料目錄，再把 `User/` 子目錄 symlink 到 `$HOME/.config/VSCodium/User`：同一個帳號同時開兩個 session，兩個 VSCodium 能不能各自獨立運作，設定又能共用？
  7. ssh_config 加上 `ControlMaster auto`、`ControlPath /tmp/ssh-cm-%i-%C`、`ControlPersist 30m` 之後，Open Remote-SSH 還能正常連線嗎？斷線重連時是否真的不用再輸入密碼？（B4）
  8. 把 extension 目錄直接複製到 `--extensions-dir`（不透過 `--install-extension`）時，VSCodium 會不會載入？`extensions.json` 註冊表要怎麼更新，才能讓「換掉舊版本」生效，而且不會影響使用者自己裝的 extension？（B5）
- [ ] **Step 3：Commit**

```bash
git add docs/spike-notes.md
git commit -m "docs: record spike results and pinned versions"
```

> 如果第 3 題的結論是 Open Remote-SSH 沒辦法在 tkadm 上運作，就**停下來回報**，因為這會推翻 D2 的決定。

---

### Task 1：Repo 初始化與 ssh-config 產生器

**Files:**
- Create: `LICENSE`、`.gitignore`（忽略 `tests/e2e/out/`）、`tests/lib.sh`
- Create: `rootfs/opt/rdp-vscode/ssh-config.sh`
- Test: `tests/unit/ssh-config.test.sh`

**Interfaces:**
- Produces：`ssh-config.sh` 會把 ssh_config 輸出到 stdout。它讀取的環境變數見 §1.3；ConfigMap 路徑可以用 `RDP_VSCODE_SSH_CONFIG` 覆寫（預設 `/etc/rdp-vscode/ssh/config`，主要給測試用）。`SSH_PORT` 不是 1–65535 的整數，或 `SSH_HOST_ALIAS` 含有空白時，exit 1 並輸出 `[entrypoint] invalid ...` 到 stderr
- Produces：`tests/lib.sh` 提供 `pass`、`bad`、`say`、`finish` 四個函式（`finish` 會在有任何失敗時 exit 1）

- [ ] **Step 1：`git init -b main`，加入 Apache-2.0 的 `LICENSE`、`.gitignore` 和 `tests/lib.sh`**
- [ ] **Step 2：寫失敗的測試** `tests/unit/ssh-config.test.sh`，涵蓋以下情境：
  - `defaults`：不設任何環境變數時，輸出完全等於：
    ```
    Host tkadm
      HostName tkadm.taroko
      Port 22100
      User bigred
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      ControlMaster auto
      ControlPath /tmp/ssh-cm-%i-%C
      ControlPersist 30m
    ```
    （如果 Task 0 第 7 題的結論是不相容，就拿掉最後三行）
  - `env-override`：`SSH_HOST_ALIAS=lab SSH_HOST=10.0.0.5 SSH_PORT=22 SSH_USER=alice` 時，輸出中對應的 4 行都有正確替換
  - `configmap-wins`：`RDP_VSCODE_SSH_CONFIG` 指向一個內容是 `Host foo` 的檔案時，輸出就是那個檔案的內容（逐 byte 相同）
  - `empty-configmap`：檔案存在但大小為 0 時，輸出等於 `defaults` 的結果
  - `bad-port`：`SSH_PORT=abc` 和 `SSH_PORT=70000` 都會 exit 1
- [ ] **Step 3：執行 `bash tests/unit/ssh-config.test.sh`，預期 FAIL（腳本還不存在）**
- [ ] **Step 4：實作 `rootfs/opt/rdp-vscode/ssh-config.sh`**
- [ ] **Step 5：執行 `bash tests/unit/ssh-config.test.sh`，預期全部 PASS；再跑 `shellcheck rootfs/opt/rdp-vscode/ssh-config.sh`（主機上沒有就用 `podman run --rm -v "$PWD:/m:Z" docker.io/koalaman/shellcheck:stable /m/...`），預期沒有警告**
- [ ] **Step 6：Commit**：`feat: add ssh_config generator with env and ConfigMap sources`

---

### Task 2：Base image（Dockerfile）

**Files:**
- Create: `Dockerfile`
- Test: `tests/image/smoke.test.sh`

**Interfaces:**
- Consumes：Task 0 的 3 個版本號
- Produces：`localhost/rdp-vscode:dev`，裡面有：
  - `/usr/bin/codium`
  - `/opt/rdp-vscode/extensions/` 裡的 Open Remote-SSH 和繁中語言包（目錄名稱格式 `<publisher>.<name>-<version>`，全部小寫）
  - `xrdp`、`xrdp-sesman`、`tini`、`openbox`、`dbus-launch`、`ssh`
  - `/opt/rdp-vscode/*.sh`（從 `rootfs/` 複製進來）
- Produces：build args `VSCODIUM_VERSION`、`OPEN_REMOTE_SSH_VERSION`、`ZH_HANT_VERSION`、`WITH_FIREFOX`（預設 `0`，Task 5 才實作內容）

- [ ] **Step 1：寫失敗的測試** `tests/image/smoke.test.sh <image>`：用 `podman run --rm --entrypoint` 在 image 裡逐一檢查：
  - `codium --version` 的第一行等於 `VSCODIUM_VERSION`（從 Dockerfile 的 `ARG` 讀出來比對）
  - `/opt/rdp-vscode/extensions` 裡有 `jeanp413.open-remote-ssh-<ver>` 和 `ms-ceintl.vscode-language-pack-zh-hant-<ver>`；`/etc/skel/.vscode-oss` **不存在**
  - `command -v xrdp xrdp-sesman tini openbox dbus-launch ssh` 全部都找得到
  - `fc-list :lang=zh-tw` 不是空的；`locale -a` 有 `zh_TW.utf8`
  - `/etc/xrdp/xrdp.ini` 裡沒有 `[Xvnc]` 區段，並且有 `rdpdr=false`、`rdpsnd=false`；`sesman.ini` 有 `Policy=Separate`、`KillDisconnected=true`、`DisconnectedTimeLimit=120`、`AllowRootLogin=false`
  - image 裡**沒有** `/etc/xrdp/key.pem`、`/etc/xrdp/cert.pem`、`/etc/xrdp/rsakeys.ini`（必須在執行時才產生）
  - `/etc/ssh/ssh_config` 有 `Include /etc/ssh/ssh_config.d/*.conf`
- [ ] **Step 2：執行測試，預期 FAIL（image 還不存在）**
- [ ] **Step 3：寫 Dockerfile。** layer 的順序：
  1. apt 套件：`xrdp xorgxrdp openbox dbus-x11 fonts-noto-cjk locales tini openssh-client openssl ca-certificates curl xdg-utils`
  2. 產生 locale
  3. 下載指定版本的 `.deb`，並用 `curl -fsI` 確認 `reh-alpine-x64` 存在（不存在就讓 build 失敗），再 `apt install ./codium.deb`
  4. 下載 `.vsix`，用 `codium --install-extension ... --extensions-dir /opt/rdp-vscode/extensions` 裝進 image（或依照 Task 0 第 8 題的結論直接解壓）
  5. 用 sed 修改 xrdp.ini 和 sesman.ini（參考 rdp-firefox 的 Dockerfile 第 30–43 行），刪掉 build 時產生的金鑰
  6. `COPY rootfs/ /`
  7. `ARG WITH_FIREFOX`（最後一層）

  `ENV LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 TZ=Asia/Taipei`；`ENTRYPOINT ["/usr/bin/tini","--"]`；`CMD ["/opt/rdp-vscode/entrypoint.sh"]`；`EXPOSE 3389`。
- [ ] **Step 4：`podman build -t localhost/rdp-vscode:dev .`，再執行 `bash tests/image/smoke.test.sh localhost/rdp-vscode:dev`，預期全部 PASS**
- [ ] **Step 5：Commit**：`feat: add Debian base image with pinned VSCodium and xrdp`

---

### Task 3：Entrypoint 與帳號管理

**Files:**
- Create: `rootfs/opt/rdp-vscode/accounts.sh`、`rootfs/opt/rdp-vscode/entrypoint.sh`
- Test: `tests/unit/accounts.test.sh`（在 image 內執行）

**Interfaces:**
- Consumes：`ssh-config.sh`（Task 1）
- Produces：`accounts.sh [users-file]`：讀取 `user:password` 格式的帳號（沒有檔案時讀 `RDP_USER`（預設 `bigred`）和 `RDP_PASSWORD`），建立或更新帳號，最後在 stdout 列出所有帳號名稱，以空白分隔。驗證規則和錯誤訊息沿用 rdp-firefox `entrypoint.sh` 第 21–43 行，但改用 Debian 的 `useradd -M -u <uid> -s /bin/bash`。home 不存在時才 `cp -a /etc/skel` 建立，並設為 `chmod 700`；home 已存在但 UID 不同時，就 `chown -R` 給新的 UID
- Produces：`entrypoint.sh`：以 root 身分依序執行 `accounts.sh`、`ssh-config.sh > /etc/ssh/ssh_config.d/rdp-vscode.conf`、產生 TLS 和 RSA 金鑰（只在不存在時）、清除殘留的 lock 檔、建立 `/tmp/sess`（1777）、設定 `MaxSessions`，然後啟動 `xrdp-sesman --nodaemon` 和 `xrdp --nodaemon`，最後 `wait -n`（任何一個程序結束就讓容器退出）

- [ ] **Step 1：寫失敗的測試** `tests/unit/accounts.test.sh`，在 `podman run --rm --entrypoint bash localhost/rdp-vscode:dev` 裡執行以下情境：
  - `default-bigred`：沒有 users 檔，`RDP_PASSWORD=bigred` 時，建立 `bigred`（uid 1000），`/home/bigred/.bashrc` 存在（證明 home 是從 skel 建立的；`rc.xml` 的檢查在 Task 4），而且密碼雜湊比對成功（見下方的「密碼驗證方法」）
  - `home-private`（B3）：建立 alice 和 bob 後，`stat -c %a /home/alice` 是 `700`；`su bob -c 'ls /home/alice'` 會失敗；`bob` 不在 `sudo` 群組，image 裡也沒有 `sudo` 指令
  - `users-file`：users 檔內容為 `alice:a1` 和 `bob:b:2` 時，alice 是 1000、bob 是 1001，bob 的密碼雜湊比對 `b:2` 成功（密碼可以含冒號），比對 `b` 則失敗
  - `reject`：`root:x`、`Bad:x`、`alice:`、重複的 alice，每一種都會 exit 1
  - `keep-home`：`/home/alice/marker` 已經存在時，執行後檔案還在，skel 沒有蓋過它
  - `uid-reorder`（Review Focus 2）：模擬 pod 重啟，`/etc/passwd` 回到乾淨狀態，只保留 `/home`。第一個容器用 `alice,bob` 的順序執行，並在 `/home/alice/f` 建立一個檔案；**第二個新容器**掛載同一個 `/home` volume（`podman volume`），用 `bob,alice` 的順序執行。斷言：`id -u bob` = 1000、`id -u alice` = 1001；`stat -c %u` 檢查 `/home/alice` 和 `/home/alice/f` 都是 1001，`/home/bob` 是 1000
  - **密碼驗證方法**（測試以 root 執行，`su` 不會檢查密碼，所以不能用）：用 `getent shadow <user>` 取出雜湊，切出 salt（`$6$<salt>$...` 的中間那段），再用 `openssl passwd -6 -salt <salt> '<密碼>'` 算出雜湊，必須跟 shadow 裡的值完全相同；**反向檢查**：用錯誤的密碼算出來的雜湊必須不同。如果 Debian 預設的雜湊不是 SHA-512（`$6$`），例如是 yescrypt（`$y$`），就在 `accounts.sh` 呼叫 `chpasswd -c SHA512` 固定演算法
- [ ] **Step 2：rebuild image 後執行測試，預期 FAIL**
- [ ] **Step 3：實作 `accounts.sh` 和 `entrypoint.sh`**
- [ ] **Step 4：rebuild image 後執行測試，預期 PASS。** 另外做一次 smoke 檢查：`podman run -d --name rdp-vscode-smoke -e RDP_PASSWORD=bigred -p 33390:3389 localhost/rdp-vscode:dev`，10 秒內 `nc -z 127.0.0.1 33390` 要成功，`podman exec ... cat /etc/ssh/ssh_config.d/rdp-vscode.conf` 要等於 Task 1 的 `defaults` 輸出；檢查完執行 `podman rm -f rdp-vscode-smoke`
- [ ] **Step 5：Commit**：`feat: add entrypoint with account management and per-pod TLS`

---

### Task 4：Session（kiosk VSCodium、自動連線、關閉就登出）

**Files:**
- Create: `rootfs/etc/xrdp/startwm.sh`
- Create: `rootfs/etc/skel/.config/openbox/rc.xml`、`rootfs/etc/skel/.config/VSCodium/User/settings.json`
- Create: `tests/e2e/client/Dockerfile`、`tests/e2e/client/login.sh`（從 `~/rdp-firefox/github/firefox-rdp/.claude/worktrees/pub/test/e2e/client/` 複製）
- Test: `tests/image/session.test.sh`

**Interfaces:**
- Consumes：Task 0 第 1、2、4、5、6、8 題的結論；Task 3 的 entrypoint
- Produces：`rootfs/opt/rdp-vscode/sync-extensions.sh <user-extensions-dir>`（以登入的使用者身分在 startwm.sh 裡執行，在啟動 codium 之前）：對 `/opt/rdp-vscode/extensions` 裡的每個 `<publisher>.<name>-<version>`，刪掉使用者目錄裡同 `<publisher>.<name>` 但版本不同的目錄，再複製 image 的版本過去，並依照 Task 0 第 8 題的結論更新 `extensions.json`；其他 extension 不動。如果版本已經一樣就什麼都不做（重複執行結果相同）
- Produces：每個 session 的資料目錄 `S=/tmp/sess/<display>.<uid>`，裡面有 `$S/data`（`--user-data-dir`，其中 `$S/data/User` → `$HOME/.config/VSCodium/User` 的 symlink）和 `$S/run`（`XDG_RUNTIME_DIR`）
- Produces：codium 的啟動參數：`--user-data-dir "$S/data" --extensions-dir "$HOME/.vscode-oss/extensions" --locale "$VSCODIUM_LOCALE"`，再加上 Task 0 決定的 sandbox 和前景參數；`SSH_HOST_ALIAS` 不是空的時，再加 `--remote "ssh-remote+$SSH_HOST_ALIAS" "$SSH_REMOTE_FOLDER"`
- Produces：startwm.sh 的行為：用 `codium ... & wait $!` 啟動 codium（**不可以在前景執行**：bash 在前景子程序結束前會延後 trap，斷線時 sesman 送來的 SIGTERM 就不會觸發清理）。設定 `trap cleanup EXIT` 和 `trap 'exit 143' TERM HUP INT`（同 rdp-firefox）。codium 結束或收到訊號 → 執行 cleanup（結束 dbus、殺掉子程序、`rm -rf $S`）→ exit，xrdp session 跟著結束。**不像 rdp-firefox 那樣用 while 迴圈重開**

設定檔內容：
- `rc.xml`：跟 rdp-firefox 一樣讓所有視窗最大化、無邊框，另外加上 `A-Tab` → `NextWindow` 的快捷鍵（讓 `-firefox` 版本能切換視窗）
- `settings.json`：`"update.mode": "none"`、`"extensions.autoUpdate": false`、`"telemetry.telemetryLevel": "off"`、`"yaml.schemas": {"kubernetes": ["*.yaml", "*.yml"]}`，以及 Task 0 第 4、5 題決定的「遠端自動安裝 yaml」和「叢集網址用 Simple Browser 開啟」設定

- [ ] **Step 1：寫失敗的測試** `tests/image/session.test.sh`：用 podman 啟動 image（`-e RDP_PASSWORD=bigred`，加上 `--dns 10.98.0.10 --dns-search svc.tk8s.k8s`，讓容器能用叢集 DNS 解析 `tkadm.taroko`，SSH 設定維持預設值（port 22100 由 ssh config 提供）；已驗證過：host 連不到 NodePort 32200，但連得到 ClusterIP），再用 e2e client 登入，檢查以下情境：
  - `kiosk`：`/home/bigred/.config/openbox/rc.xml` 存在；登入 30 秒內，`ps` 裡出現屬於 bigred、參數含 `ssh-remote+tkadm` 和 `--locale zh-tw` 的 codium 程序；截圖存到 `tests/e2e/out/`
  - `locale-en`：用 `-e VSCODIUM_LOCALE=en` 重新啟動，codium 程序的參數含 `--locale en`（AC10）
  - `close-logout`：用 `pkill -u bigred -f /usr/share/codium` 模擬關閉 VSCodium，15 秒內 bigred 的 `Xorg` 程序消失，`/tmp/sess/*.1000` 也被清掉（AC7）
  - `same-account-twice`（Review Focus 1）：兩個 client 同時用 bigred 登入，會有兩個 Xorg，各自有一個 codium 主程序，而且兩個程序的 `--user-data-dir` 不同
  - `disconnect-cleanup`（Review Focus 4）：直接 `podman rm -f` 掉 client（模擬斷線），150 秒內 bigred 的 codium 程序全部消失，**而且 `/tmp/sess/*.1000` 已被刪除**（證明 trap 有執行清理）
  - `settings-shared`：寫入 `/home/bigred/.config/VSCodium/User/settings.json` 的值，在 `$S/data/User/settings.json` 也讀得到
  - `ext-sync`（B5）：先在 `/home/bigred/.vscode-oss/extensions` 放一個假的舊版 `jeanp413.open-remote-ssh-0.0.1` 和一個使用者自己裝的 `foo.bar-1.0.0`，登入後，舊版消失、image 版本出現，`foo.bar-1.0.0` 還在；再登入一次，目錄內容完全不變（重複執行結果相同）
- [ ] **Step 2：rebuild image 後執行測試，預期 FAIL**
- [ ] **Step 3：實作 `sync-extensions.sh`、`startwm.sh`、`rc.xml`、`settings.json`**
- [ ] **Step 4：rebuild image 後執行測試，預期 PASS**
- [ ] **Step 5：手動檢查一次截圖：畫面是全螢幕 VSCodium、繁中介面，並跳出 tkadm 的密碼框**
- [ ] **Step 6：Commit**：`feat: add kiosk VSCodium session with auto remote connect`

---

### Task 5：Firefox 版本（`WITH_FIREFOX=1`）

**Files:**
- Modify: `Dockerfile`（最後一層 `WITH_FIREFOX`）
- Create: `rootfs-firefox/etc/xdg/mimeapps.list`
- Modify: `tests/image/smoke.test.sh`（加上 `--firefox` 模式）

**Interfaces:**
- Produces：`localhost/rdp-vscode:dev-firefox`。`WITH_FIREFOX=1` 時，`apt install firefox-esr`、複製 `rootfs-firefox/`，並把 `x-scheme-handler/http`、`x-scheme-handler/https`、`text/html` 都指向 `firefox-esr.desktop`。前面所有 layer 跟預設 tag 共用

- [ ] **Step 1：在 smoke 測試加上這些情境：** `--firefox` 模式下，image 裡有 `firefox-esr`，並且用 bigred 身分執行 `xdg-mime query default x-scheme-handler/https` 會得到 `firefox-esr.desktop`；預設模式下，`command -v firefox-esr` 找不到（反向檢查）
- [ ] **Step 2：用兩種 build arg 各 build 一次，並各跑一次測試。預期 firefox 版 FAIL、預設版 PASS**
- [ ] **Step 3：實作 Dockerfile 的最後一層和 `mimeapps.list`**
- [ ] **Step 4：兩種 build 都跑測試，預期都 PASS；並確認 `podman image tree` 顯示兩個 tag 只差最後一層**
- [ ] **Step 5：Commit**：`feat: add WITH_FIREFOX build arg for firefox-esr variant`

---

### Task 6：Kustomize 部署（base、stateless、stateful、ConfigMap 範例）

**Files:**
- Create: `deploy/base/{kustomization,namespace,deployment,service}.yaml`
- Create: `deploy/stateless/{kustomization.yaml,users.txt,home-emptydir.yaml}`
- Create: `deploy/stateful/{kustomization.yaml,users.txt,pvc.yaml,home-pvc.yaml}`
- Create: `deploy/example/ssh-configmap/{kustomization.yaml,ssh_config}`
- Test: `tests/deploy/render.test.sh`

**Interfaces:**
- Produces：base 參照 rdp-firefox 的 `deploy/base`，但把值換成 §1.4 和 §1.3 的設定：
  - namespace `rdp-vscode`、NodePort `30390`
  - 資源：requests 500m/1Gi，limits 4/4Gi
  - `/dev/shm` 用 1Gi 的記憶體 emptyDir
  - 環境變數：`MAX_SESSIONS=3`，以及所有 `SSH_*` 和 `VSCODIUM_LOCALE` 的預設值
  - Secret `rdp-vscode-users` 掛到 `/etc/rdp-vscode/users`
  - ConfigMap `rdp-vscode-ssh` 掛到 `/etc/rdp-vscode/ssh`，設 `optional: true`
  - base 不掛 `/home`
- Produces：stateless overlay 用 patch 把 emptyDir 掛到 `/home`；stateful overlay 用 patch 掛 PVC `rdp-vscode-home`（5Gi、RWO、**沒有 `storageClassName` 欄位**）。兩個 overlay 的 `users.txt` 預設內容都是 `bigred:bigred`，開頭有註解提醒要修改密碼（B6），並由 secretGenerator 產生 Secret
- Produces：`deploy/example/ssh-configmap` 以 `../../stateless` 為基礎，用 configMapGenerator 產生 `rdp-vscode-ssh`（key `config`）

- [ ] **Step 1：寫失敗的測試** `tests/deploy/render.test.sh`：對每個 overlay 執行 `kubectl kustomize`，用 `yq` 或 `grep` 驗證：
  - 所有資源都在 namespace `rdp-vscode`
  - Service 的 nodePort 是 30390
  - limits 是 4/4Gi
  - stateless 有 `/home` 的 emptyDir，**沒有** PVC
  - stateful 有 PVC，`storage: 5Gi`，**沒有** `storageClassName`；Deployment 用 `Recreate`
  - ssh-configmap 範例有 `rdp-vscode-ssh` ConfigMap

  最後對每個 overlay 都跑一次 `kubectl apply --dry-run=server -k`，預期成功
- [ ] **Step 2：執行測試，預期 FAIL**
- [ ] **Step 3：寫好所有 manifest**
- [ ] **Step 4：執行測試，預期 PASS**
- [ ] **Step 5：Commit**：`feat: add kustomize base with stateless and stateful overlays`

---

### Task 7：tk8s 上的 e2e 驗收

**Files:**
- Create: `tests/e2e/run.sh`
- Create: `tests/e2e/manual-checklist.md`（列出需要手動確認的 AC3、AC5、AC6、AC9 步驟）

**Interfaces:**
- Consumes：Task 2–6 的所有產出
- Produces：`tests/e2e/run.sh [stateless|stateful|all]`（不含 firefox 模式，見第 5/10 項：AC9 的自動部分在 Task 5 用 podman 驗證，畫面部分列在手動清單）。流程如下：
  1. build image
  2. 用 rdp-firefox `build-image.md` 裡的 `podman --root .../$n-var/... load` 方法，把 image 載入 tk8s-worker-1 和 tk8s-worker-2
  3. 用 kustomize 的 `images:` 把 image 換成 `localhost/rdp-vscode:dev`，再 apply
  4. 用 `kubectl port-forward svc/rdp-vscode 33390:3389` 轉發 RDP
  5. 用 e2e client 登入，逐項驗證，輸出 `PASS`/`FAIL`
  6. 最後清掉 namespace（設 `E2E_KEEP=1` 就保留）

- [ ] **Step 0：tk8s 前置作業（B2，執行前必須先經使用者同意）。** 先備份 `kubectl get sc local-path -o yaml`，再刪除並重建 `local-path` SC，只把 `volumeBindingMode` 改成 `WaitForFirstConsumer`，其他欄位不變，並保留 default 的 annotation。驗證：`kubectl get sc local-path -o jsonpath='{.volumeBindingMode}'` 輸出 `WaitForFirstConsumer`。注意：已經 Pending 的 vault PVC 可能還要另外處理，那不在本專案的範圍內，只回報狀態
- [ ] **Step 1：寫 `run.sh`，涵蓋以下自動化檢查：**
  - AC1：`kubectl wait --for=condition=Ready pod -l app=rdp-vscode --timeout=180s`
  - AC2：登入後，pod 裡出現 bigred 的 Xorg
  - AC3（自動部分）：codium 程序參數含 `ssh-remote+tkadm`；輸入密碼**之前**，先在 tkadm 上 `touch /tmp/rdp-vscode-e2e.marker`；再用 xdotool 在密碼框輸入 `bigred` 並按 Enter，90 秒內 `find ~/.vscodium-server -newer /tmp/rdp-vscode-e2e.marker` 要有輸出（或出現比 marker 新的 server 程序）。**不可以刪除 `~/.vscodium-server`**，因為 tkadm 是共用的
  - AC4 和 AC5（自動部分）：在 tkadm 執行 `kubectl create deploy web --image=nginx` 和 `kubectl expose deploy web --port 80`，然後 `kubectl -n rdp-vscode exec deploy/rdp-vscode -- curl -fsS http://web.default.svc.tk8s.k8s` 的輸出要含 `Welcome to nginx`。測試結束時刪掉 `web`
  - AC6（自動部分）：tkadm 的 `~/.vscodium-server/extensions` 裡有 `redhat.vscode-yaml-*`
  - AC7：同 Task 4 的 `close-logout`
  - AC8（stateful 模式）：在 `/home/bigred/.config/VSCodium/User/settings.json` 寫入 `"editor.fontSize": 17`，刪掉 pod，等新 pod Ready 後，**用 e2e client 重新登入一次**，檢查這個新 session 的 `/tmp/sess/<display>.1000/data/User/settings.json`（symlink 到 home）讀到的是 17。畫面上的字型有沒有真的變大，列在 `manual-checklist.md`
  - AC9：不在 e2e 驗證；Task 5 已經用 podman 驗過 `xdg-mime`，畫面部分列在 `manual-checklist.md`
  - AC10：用 `kubectl set env VSCODIUM_LOCALE=en` 重新部署後，codium 參數含 `--locale en`
  - Review Focus 5：用 `kubectl set env SSH_HOST=nonexistent.invalid` 重新部署並登入，60 秒後 bigred 的 Xorg **還在**（session 沒有被登出）
- [ ] **Step 2：執行 `bash tests/e2e/run.sh all`，預期全部 PASS；截圖存在 `tests/e2e/out/`**
- [ ] **Step 3：寫好 `manual-checklist.md`，請使用者手動檢查 AC3、AC5、AC6、AC8（畫面字型）、AC9 的畫面**
- [ ] **Step 4：Commit**：`test: add tk8s end-to-end acceptance script`

---

### Task 8：文件與發佈

**Files:**
- Create: `README.md`（英文）、`README.zh-TW.md`、`build-image.md`、`user-guide.md`

**Interfaces:**
- Consumes：所有 task 的實際指令和結論

- [ ] **Step 1：`README.md` 和 `README.zh-TW.md`**：內容相同、互相連結，包含：
  - 這是什麼
  - 架構圖（文字版：RDP client → NodePort 30390 → xrdp → VSCodium → SSH → tkadm）
  - 快速部署（`kubectl apply -k deploy/stateless`）
  - 環境變數表（§1.3）
  - stateless 和 stateful 的差異
  - 資源估算（每多一人加 1Gi）
  - **開頭的安全警告**（B6）：預設帳密 bigred/bigred 只適合隔離的實驗環境；能連到 NodePort 的人，就能經由 RDP → 叢集內網路 → tkadm → kubectl 控制整個叢集
  - 儲存需求（B2）：stateful 模式需要預設 SC 是 `WaitForFirstConsumer` 或網路儲存；說明 local-path 綁定節點的限制
  - 叢集內網址：`SSH_HOST` 預設用短名稱 `tkadm.taroko`，在任何 cluster domain 都能用；瀏覽網站時可以用短名稱 `<svc>.<ns>`，也可以用完整 FQDN `<svc>.<ns>.svc.<cluster-domain>`。cluster domain 不一定是 `cluster.local`（例如 tk8s 是 `tk8s.k8s`），可以從 CoreDNS 的 Corefile 查到
  - 已知限制：
    - 所有 RDP 帳號共用 tkadm 上的 bigred（B1）
    - tkadm 重啟後會重新下載 server
    - 只能用 Open VSX 的 extension，不支援 Pylance、Copilot 等微軟專屬 extension
    - image 大約 1.2GB
  - 授權：Apache-2.0
- [ ] **Step 2：`build-image.md`**：延續 rdp-firefox 的繁中逐步教學風格。用 podman 分別 build 兩個 tag、跑 smoke 測試、載入 tk8s 節點，再推到 ghcr.io（`podman login ghcr.io`，用 PAT）。如何升級 `VSCODIUM_VERSION` 也要寫
- [ ] **Step 3：`user-guide.md`**：說明 Windows 遠端桌面怎麼連、輸入 tkadm 密碼、在 tkadm 部署網站、用 Simple Browser 打開 FQDN、中文怎麼透過剪貼簿貼上、`-firefox` 版本怎麼用 Alt-Tab 切換視窗
- [ ] **Step 4：照著 `build-image.md` 和 `user-guide.md` 從頭走一遍，確認每個指令都能照貼執行**
- [ ] **Step 5：Commit**：`docs: add README, build guide and user guide`
- [ ] **Step 6：發佈（必須先經使用者同意）**：在 GitHub 建立 `braveantony/rdp-vscode` 並 push；`podman push` 兩個 tag 到 ghcr.io，並把 package 設為 public
- [ ] **Step 7：在 repo 建立 GitHub issue（必須先經使用者同意，跟 Step 6 一起確認）**：標題 `e2e: cover the -firefox variant on a real cluster`，內容寫明：目前 `-firefox` tag 的驗證範圍（Task 5 的 podman `xdg-mime` 檢查，以及 manual-checklist 的 AC9 畫面確認）；e2e 沒有涵蓋的部分（叢集上部署 `dev-firefox`、Firefox 在 pod 內用 FQDN 開網站、從 VSCodium 點連結開 Firefox、Alt-Tab 切換視窗）；未來的實作方向（`run.sh firefox` 模式：`WITH_FIREFOX=1` build、載入節點、kustomize `newTag: dev-firefox`）

---

## 第 3 部分：Task 相依關係

```
Task 0 (spike) ──┬─> Task 2 (image) ──> Task 3 (entrypoint) ──> Task 4 (session) ──> Task 5 (firefox)
Task 1 (ssh-cfg) ┘                                                    │
                                          Task 6 (kustomize) ─────────┴──> Task 7 (e2e) ──> Task 8 (docs/release)
```

Task 1 和 Task 6 不依賴 Task 0，可以先平行進行。
