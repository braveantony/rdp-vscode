# Task 0 技術驗證紀錄

驗證日期：2026-10-27。環境：拋棄式容器 `debian:trixie-slim` + VSCodium，用 `--dns 10.98.0.10 --dns-search svc.tk8s.k8s` 連 tk8s 的 tkadm。

## 版本（Step 1）

| 項目 | 版本 | 備註 |
|---|---|---|
| VSCodium | `1.143.17183`（2026-10-26） | 同一 release 有 `codium_1.143.17183_amd64.deb` 與 `vscodium-reh-alpine-x64-1.143.17183.tar.gz` |
| Open Remote-SSH | `0.5.1` | `engines.vscode: ^1.70.2` |
| 繁中語言包 | `1.131.0` | `engines.vscode: ^1.131.0`；Open VSX 上最新版，比 VSCodium 舊 12 個 minor 版，翻譯完整度待確認 |
| redhat.vscode-yaml（不固定） | `2.1.2026102308` | 僅記錄 |

## 結論

| # | 問題 | 結論 |
|---|---|---|
| 1 | 需要 `--no-sandbox` 嗎？ | **不需要**。非 root 執行，即使加上 `no-new-privileges`（模擬 K8s 的 `allowPrivilegeEscalation: false`），renderer 仍正常啟動。K8s（cri-o）上的最終確認留給 Task 7 |
| 3 | Open Remote-SSH 能連 tkadm 嗎？ | **可以，但 tkadm 的 sshd 必須是 `AllowTcpForwarding local`**（原本是 `no`，已修改，見 [ops 紀錄](ops/2026-10-27-tkadm-sshd-forwarding.md)）。修改後用預設的 TCP 模式：密碼只問一次、`reh-alpine-x64`（約 92MB）下載並啟動、只有 `attempt #1` 沒有重連，標題列 `bigred [SSH: tkadm]` |
| 4 | `redhat.vscode-yaml` 怎麼自動裝到遠端？ | **用 `remote.SSH.defaultExtensions: ["redhat.vscode-yaml"]`**。server 啟動參數會帶 `--install-extension redhat.vscode-yaml`，實測裝到 `~/.vscodium-server/extensions/redhat.vscode-yaml-2.0.0-universal`。注意：server 裝的是 2.0.0，不是 Open VSX 頁面上的 2.1.2026102308 |
| 8 | 直接複製 extension 目錄會被載入嗎？ | 只有在 `extensions.json` **不存在**時會。存在時，新目錄不會被載入，舊的註冊項目也會繼續生效。改用 `codium --extensions-dir <dir> --install-extension <vsix> --force`：會正確換掉舊版本、保留使用者自己裝的 extension，每次約 0.3 秒 |
| 2 | `codium & wait $!` 會等到視窗關閉嗎？斷線時 trap 會清理嗎？ | **`codium` 不行，要直接執行 `/usr/share/codium/codium`**。`/usr/bin/codium` 是啟動器，會把主程式丟到背景後 1 秒內就結束，`wait` 等不到視窗關閉。直接執行 Electron 主程式時：按 Ctrl+Q 關閉後 `wait` 才返回；對腳本送 SIGTERM，`trap 'exit 143' TERM` + `trap cleanup EXIT` 在 1 秒內結束所有 codium 程序並刪除 session 目錄。sesman 斷線 120 秒後是否真的送 SIGTERM，留給 Task 4 的 `disconnect-cleanup` 測試 |
| 5 | 叢集網址能不能預設用 Simple Browser 開？ | **不能自動，改用 Integrated Browser 手動開**。Simple Browser 的開啟器只接受 `localhost`、`127.0.0.1` 等位址，其他主機一律回傳 None，`workbench.externalUriOpeners` 也沒用。VSCodium 1.143 內建新的 Integrated Browser（指令 `Browser: Open Integrated Browser`，標題列也有地球圖示），輸入 `http://dkreg.taroko.svc.tk8s.k8s:5000/v2/` 可以正常顯示。從遠端 terminal 用 `$BROWSER` 開網址，會跳出「是否開啟外部網站」確認框，再交給系統瀏覽器 |
| 6 | 每個 session 獨立資料目錄、`User/` 用 symlink 共用可行嗎？ | **可行**。同一個帳號在 `:5`、`:6` 同時開兩個 VSCodium（`/tmp/sess/<display>.1000/data`，`data/User` → `~/.config/VSCodium/User`），兩個各自有視窗和程序；關掉一個，另一個不受影響。注意：`User/globalStorage` 也會被兩個 session 共用 |
| 7 | ControlMaster 跟 Open Remote-SSH 相容嗎？ | **沒有作用**。Open Remote-SSH 用內建的 `ssh2` 函式庫連線，不呼叫系統的 `ssh`，加了 ControlMaster 也不會產生 socket。Reload Window 時會再問一次密碼 |

## Q3 第一次受阻的原因（已解決）

1. 密碼框會正常跳出，server（`reh-alpine-x64`）也會成功下載並在 tkadm 上啟動，標題列會出現 `[SSH: tkadm]`。
2. 但 VSCodium 必須透過 SSH 轉發連到 tkadm 上的 server，而 **tkadm 的 sshd 設定是 `AllowTcpForwarding no`**：
   - TCP 模式：轉發失敗，VSCodium 不斷重新連線（attempt #2、#3…），每次都再要一次密碼
   - Unix socket 模式（`remote.SSH.remoteServerListenOnSocket: true`）：用 OpenSSH 直接測試 `-L 127.0.0.1:9998:/tmp/vscode-server-sock-…`，得到 `channel 1: open failed: connect failed: open failed`。OpenSSH 在 `AllowTcpForwarding no` 時，會連 `direct-streamlocal` 一起拒絕，即使 `AllowStreamLocalForwarding yes`
3. 在 tkadm 裡直接用 `curl --unix-socket` 連 server 是正常的（HTTP 403），所以 server 本身沒問題，問題只出在 sshd 的轉發限制。

## 其他發現

- Open Remote-SSH 會讀取 `/etc/ssh/ssh_config`（含 `Include ssh_config.d/*.conf`），但它的 fallback 路徑會以 `-F ~/.ssh/config` 執行系統的 ssh，這個檔案不存在時會失敗
- Debian 預設的 `GSSAPIAuthentication yes` 會觸發 fallback 路徑，要在 Host 區塊加上 `GSSAPIAuthentication no`
- `UserKnownHostsFile /dev/null` 會讓 extension 每次連線都跳出 host key 確認視窗，需要設定 `remote.SSH.verifyUnknownHosts: "accept"`
- Open Remote-SSH 0.5.1 自己就會管理 ssh ControlMaster，我們加的 ControlMaster 設定（B4）可能多餘
- VSCodium 的 log 存放在 `~/.local/state/VSCodium/`，不在 `--user-data-dir` 裡；另外還有 `~/.vscode-oss-shared/` 共用 storage。這兩者都與 Q6（同帳號同時登入兩次）有關
- spike 容器沒有 init，結束的 codium 會變成 zombie；正式 image 用 tini 回收，不受影響
- 遠端 terminal 的 `$BROWSER` 是 `~/.vscodium-server/bin/<commit>/bin/helpers/browser.sh`

## 對計畫的影響（Ruling）

1. startwm.sh 改成直接執行 `/usr/share/codium/codium ... & wait $!`（Q2）
2. 拿掉 B4 的 ControlMaster 三行（Q7，06-risks 預先寫好的退路）
3. 「Simple Browser」改成「Integrated Browser」；叢集網址不會自動用內建瀏覽器開，要用指令或標題列的地球圖示開（Q5）
4. ssh config 加 `GSSAPIAuthentication no`；VSCodium 預設設定加 `remote.SSH.verifyUnknownHosts: "accept"`、`remote.SSH.defaultExtensions: ["redhat.vscode-yaml"]`（Q3、Q4）
5. sync-extensions 改用 `--install-extension <vsix> --force`，image 裡放 vsix（Q8）
6. SSH 目標的 sshd 必須至少是 `AllowTcpForwarding local`，寫進 README 的需求（Q3）
