# 01 設計決策

每個決策都附上編號，方便跟執行計畫對照：
- **D**：grilling 討論的題號
- **B**：brainstorming 盤點時補上的決策
- **A**：沒有另外討論、直接採用的假設

## 1. 產品與授權

### D1 定位：open source，不做商業用途
這份程式碼要公開，所以每個元件的**授權是否允許重新散佈**，會直接影響技術選擇。

### D2 編輯器：VSCodium + Open Remote-SSH
| 方案 | 結論 | 原因 |
|---|---|---|
| **VSCodium + `jeanp413.open-remote-ssh`** | ✅ 採用 | 兩者都是 MIT 授權，image 可以合法公開到 ghcr.io |
| Microsoft VS Code + 官方 Remote-SSH | ❌ | 授權不允許把它重新包進 image 公開；官方 Remote-SSH 也只能用在官方 VS Code 裡 |
| 只用 terminal 執行 `ssh` | ❌ | 這樣就不能直接編輯 tkadm 上的檔案 |

代價：只能用 Open VSX 上的 extension，Pylance、C# Dev Kit、Copilot 這類微軟專屬的 extension 都不能用。

### D14 名稱與授權
- GitHub repo：`braveantony/rdp-vscode`
- Image：`ghcr.io/braveantony/rdp-vscode:1.1`（Firefox 版本是 `:1.1-firefox`）
- 授權：**Apache-2.0**。它跟 VSCodium（MIT）、xrdp（Apache-2.0）相容，而且附帶專利授權。沒有 LICENSE 檔的 repo，法律上等於「保留所有權利」，別人不能合法使用

### D15 Build 方式：podman 手動 build、手動 push
跟 rdp-firefox 一樣，不做 CI。

### D16 版本固定
- VSCodium 用 `ARG VSCODIUM_VERSION` 固定版本。build 時會檢查 GitHub release 上有沒有對應的 `vscodium-reh-alpine-x64`（tkadm 要下載的 server），沒有就讓 build 失敗
- Image 裡預裝的 extension（Open Remote-SSH、繁中語言包）也固定版本
- 遠端自動安裝的 `redhat.vscode-yaml` **不固定版本**：tkadm 的 home 不會保留，每次都是從 Open VSX 裝最新版，硬要固定版本不划算

## 2. Image 內容與畫面

### D2 Base image：`debian:trixie-slim`
VSCodium 是 glibc 程式，沒辦法沿用 rdp-firefox 的 Alpine（musl）。選 trixie 是因為它跟 tk8s 節點的 OS 一致。

### D3 多使用者：一個 pod 多個帳號
沿用 rdp-firefox v3 的機制：帳號來自 `users.txt`（Secret），每條 RDP 連線各自一個 Xorg（`Policy=Separate`）。預設帳號是 bigred/bigred。

| 方案 | 結論 |
|---|---|
| **一個 pod 多帳號** | ✅ 可以重用最多 rdp-firefox 的程式碼 |
| 一人一個 pod | ❌ 每多一個人就要多一份 Deployment，或要另外寫 controller |
| 只有 bigred 一個帳號 | ❌ 不容易擴充 |

### D6 畫面：kiosk 模式，關掉 VSCodium 就登出
- openbox 只顯示 VSCodium（最大化、無邊框）
- 啟動時自動開一個連到 tkadm 的 Remote 視窗，一進來就跳出密碼框
- 關掉 VSCodium，RDP session 就結束（rdp-firefox 的 Firefox 關掉會自動重開，這裡**不一樣**）

### D7、D8 瀏覽器：預設用內建瀏覽器，Firefox 透過 build arg 加裝
- **Integrated Browser**：VSCodium 內建，在分頁裡直接打開叢集內的網站。原本的決定是 Simple Browser，Task 0 發現它只能開 `localhost` 這類網址，改用 Integrated Browser（見文末「實作後的修正」）
- **Firefox ESR**：只有用 `WITH_FIREFOX=1` build 出來的 `-firefox` tag 才有，設為 `xdg-open` 的預設瀏覽器，需要 DevTools 或瀏覽外部網站時使用

為什麼用 build arg，而不是執行時的環境變數？因為預設 image 可以少大約 310MB，做法也跟 rdp-firefox 的 `SESSION_SHARE` 一致。

### D9 Session 分享：第一版不做
先把核心功能做穩。Dockerfile 會把 optional 功能放在最後幾層，之後要加的時候不用大改。

### D17 語系：預設繁中，可以切換英文
- `VSCODIUM_LOCALE=zh-tw`（預設）或 `en`；語言包一律預裝（只有約 5MB）
- 系統：`LANG=zh_TW.UTF-8`、`TZ=Asia/Taipei`，字型用 Noto CJK
- 中文輸入：在本機打好字，透過 RDP 剪貼簿貼上，不在 pod 裡裝輸入法

### D18、B5 Extension
| Extension | 安裝在哪 | 版本 |
|---|---|---|
| Open Remote-SSH | 本地（image 預裝） | 固定 |
| 繁中語言包 | 本地（image 預裝） | 固定 |
| `redhat.vscode-yaml` | 遠端 tkadm（連線時自動安裝） | 最新版 |

**B5 版本同步**：預裝的 extension 以 `.vsix` 放在 `/opt/rdp-vscode/vsix`，每次登入時用 `codium --install-extension` 裝到使用者的 extension 目錄，版本不同就換掉，使用者自己裝的 extension 不受影響。如果只在建立 home 時從 skel 複製一次，stateful 模式升級 image 後，home 裡會留著舊版的 Open Remote-SSH 和語言包，可能跟新版 VSCodium 不相容。

### B3 本地 terminal：允許使用，做基本隔離
使用者可以在 rdp-vscode pod 裡開本地 shell，例如用 `curl` 測試網站，方便除錯。隔離方式：每個 home 權限設為 `0700`，帳號不給 sudo。

### A1～A3 直接採用的假設
- **A1**：拿掉 rdp-firefox 的 ttyd web terminal、`myssh`。VSCodium 本身就有 terminal
- **A2**：每個容器啟動時自己產生 TLS 憑證；密碼不寫進 image。原本也要讓 xrdp 降權執行，但 Debian trixie 的 xrdp 0.10.1 不支援，xrdp 的監聽程式以 root 執行
- **A3**：如果 Electron 在容器裡因為 sandbox 跑不起來，就加 `--no-sandbox`。Task 0 驗證後**不需要**

## 3. SSH 連線

### D4 認證：連線時輸入密碼
ssh_config 沒辦法存密碼。

| 方案 | 結論 | 原因 |
|---|---|---|
| **跳出密碼框，使用者輸入** | ✅ | 最單純，不需要在 tkadm 放金鑰 |
| 金鑰免密碼 | ❌ | 要把公鑰塞進 tkadm，但 tkadm 的 home 不會保留 |
| `sshpass` | ❌ | Open Remote-SSH 支援度不好 |

### B4 連線共用（ControlMaster）：已拿掉
原本的設計是第一次輸入密碼後，SSH 保留一條主連線 30 分鐘，斷線重連和同一個帳號的第二個 session 都不用再輸入密碼。Task 0 發現 Open Remote-SSH 用內建的 SSH 實作，不呼叫系統的 `ssh`，ControlMaster 沒有作用，所以拿掉這三行，改成每次連線都輸入密碼。

### D5 連線目標：用環境變數產生，可用 ConfigMap 覆蓋
- 預設 Host 是 `tkadm`，連到 `tkadm.taroko:22100`，User `bigred`
- 設定寫在 `/etc/ssh/ssh_config.d/rdp-vscode.conf`，**不修改**使用者自己的 `~/.ssh/config`
- 有掛 ConfigMap，而且內容不是空的時，就整份改用 ConfigMap 的設定

### 第 8 項 review：`SSH_HOST` 預設用短名稱 `tkadm.taroko`
review 時實際測試發現 **tk8s 的 cluster domain 是 `tk8s.k8s`，不是 `cluster.local`**。改用短名稱，靠 pod 的 search domain 解析，在任何 cluster domain 的叢集都能用。

### B1 遠端帳號：所有人共用 tkadm 的 bigred
多個 RDP 帳號（例如 alice、bob）都會以 bigred 身分登入 tkadm，共用 home、server 和 kubeconfig。需要彼此隔離時，應該一人部署一套 rdp-vscode 加 tkadm，而不是在 tkadm 上開多個帳號。

### D11a Host key
`StrictHostKeyChecking accept-new` 加上 `UserKnownHostsFile /dev/null`。tkadm 重建後 host key 會改變，這樣設定才不會讓使用者卡在警告畫面。

## 4. 部署

細節見 [03-deployment.md](03-deployment.md)。

| 編號 | 決策 |
|---|---|
| D10 | namespace `rdp-vscode`，NodePort `30390` |
| D11 | kustomize 分成 `stateless` 和 `stateful` 兩個 overlay |
| D12 | stateful：一個 PVC 掛 `/home`，Deployment 用 `Recreate` |
| B2 | PVC 不指定 SC，使用叢集預設；tk8s 的 `local-path` SC 需要先重建成 `WaitForFirstConsumer` |
| D13 | 資源以 3 人同時連線估算：requests 500m/1Gi，limits 4/4Gi |
| B6 | 維持 bigred/bigred，只在 README 和 `users.txt` 加警告 |

## 5. 文件（D19）

- `README.md`（繁中，GitHub 首頁預設顯示）和 `README.en.md`（英文）；原本是英文為預設，發佈後改成繁中為預設
- `docs/build-image.md`、`docs/user-guide.md`：繁中逐步手冊（目錄結構對齊 rdp-firefox）
- 程式碼註解和 commit message：英文

## 6. 實作後的修正

Task 0 和實作過程中發現的問題，以及對應的修改。詳細紀錄在 [docs/spike-notes.md](../spike-notes.md) 和 SDD ledger。

| 原本的設計 | 發現 | 修改 |
|---|---|---|
| D4「不需要修改 tkadm」 | tkadm 的 sshd 是 `AllowTcpForwarding no`（Alpine 預設），Open Remote-SSH 的轉發全部失敗，一直重新連線 | 經使用者同意，用 ConfigMap 讓 tkadm 改成 `AllowTcpForwarding local`（[紀錄](../ops/2026-10-27-tkadm-sshd-forwarding.md)）；README 註明 SSH 目標必須允許本機埠轉發 |
| D7 Simple Browser | Simple Browser 只能開 `localhost`、`127.0.0.1` 這類網址 | 改用 VSCodium 1.143 內建的 Integrated Browser，手動開啟；點連結不會自動用它開 |
| B4 ControlMaster | Open Remote-SSH 不呼叫系統的 `ssh` | 拿掉 |
| B5 複製 extension 目錄 | `extensions.json` 存在時，複製進去的目錄不會被載入 | 改用 `codium --install-extension <vsix> --force` |
| startwm.sh 用 `codium & wait $!` | `/usr/bin/codium` 是啟動器，1 秒內就結束 | 直接執行 `/usr/share/codium/codium` |
| `/dev/shm` 只是建議 | 用預設的 64MB 時，VSCodium 載入中文字型會崩潰 | 部署一律掛 1Gi 的記憶體 `emptyDir`；podman 測試加 `--shm-size=1g` |
| `--locale zh-tw` 就能顯示繁中 | VSCodium 第二次啟動才套用語言，每個 session 都是第一次啟動 | 啟動前由 `languagepacks.js` 產生 `languagepacks.json` |
| 容器的環境變數會帶進 session | sesman 用乾淨的環境啟動 session | entrypoint 寫出 `/run/rdp-vscode/session.env`，由 startwm.sh 讀取 |
| ssh 設定只放 Host、Port、User | Debian 預設 `GSSAPIAuthentication yes` 會讓 Open Remote-SSH 走另一條會失敗的路徑 | 加上 `GSSAPIAuthentication no`；VSCodium 設定加上 `remote.SSH.verifyUnknownHosts: "accept"` |
| tk8s 的 `local-path` SC | `Immediate`，PVC 會一直 Pending | 經使用者同意，重建成 `WaitForFirstConsumer`（[紀錄](../ops/2026-10-28-tk8s-local-path-sc.md)） |
