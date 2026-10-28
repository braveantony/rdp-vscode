# VSCodium 遠端桌面使用手冊

適用映像檔：`ghcr.io/braveantony/rdp-vscode:1.2`（`:1.2-firefox` 另見第 5 節）。安裝方式見 [README](../README.md#快速開始)。

用 Windows 內建的「遠端桌面連線」登入後，畫面上只有一個全螢幕的 VSCodium。它會自動以 SSH 連到叢集的管理 Pod `tkadm`，你在 VSCodium 裡開的檔案和終端機都在 `tkadm` 上，可以直接用 `kubectl` 管理叢集。

## 1. 連線與登入

| 項目 | 值 |
|---|---|
| 電腦 | 管理者給你的位址，例如 `192.168.11.64:3390` |
| 帳號 | 管理者發給你的帳號（預設是 `bigred`） |
| 密碼 | 管理者發給你的密碼（預設是 `bigred`） |

1. 按 `Win+R`，輸入 `mstsc`，按 Enter，開啟「遠端桌面連線」。
2. 電腦欄位填上面的位址（含 `:` 和埠號），按「連線」。
3. 出現憑證警告（「無法驗證此遠端電腦的身分識別」）時，按「是」。每個 Pod 使用自己產生的憑證，這是正常的。
4. 畫面會出現 xrdp 的登入畫面：Session 保持 `Xorg`，填入帳號和密碼，按 OK。

## 2. 連到 tkadm

1. 登入後畫面是全螢幕的 VSCodium，上方會跳出 `Enter password for bigred@tkadm.taroko`，要你輸入連到 `tkadm` 的密碼。這是第二組密碼，可能和剛才登入遠端桌面的密碼不同，請向管理者確認。
2. 輸入 `tkadm` 上 `bigred` 帳號的密碼（tk8s 上是 `bigred`，其他環境請問管理者），按 Enter。
3. 左下角變成 `SSH: tkadm`，左邊的檔案總管列出 `tkadm` 上 `/home/bigred` 的檔案，就表示連上了。

- `tkadm` 上還沒有這個版本的 vscodium-server 時（第一次連線、`tkadm` 重建後，或升級映像檔後），`tkadm` 會先下載約 90 MB，需要多等一段時間。
- 之後每次重新連線（包括「重新載入視窗」），都會再問一次密碼。
- 不小心按了取消時，按 `Ctrl+Shift+P`，執行「Developer: Reload Window」（重新載入視窗），密碼框會再出現一次。

## 3. 在 tkadm 部署網站並開啟（選用的管理範例）

以下示範用指令在叢集建立一個測試網站，再從 VSCodium 開啟，需要管理者授權。只想瀏覽既有的網站，可以直接從步驟 3 開始，輸入管理者提供的網址。

1. 按 `` Ctrl+` `` 開啟終端機。這個終端機在 `tkadm` 上執行。
2. 部署一個 nginx：

   ```bash
   kubectl -n default create deploy web --image=nginx
   kubectl -n default expose deploy web --port 80
   kubectl -n default rollout status deploy/web
   ```

3. 按 `Ctrl+Shift+P`，輸入 `Open Integrated Browser`，選「Browser: Open Integrated Browser」；或按標題列右邊的地球圖示。
4. 在網址列輸入 `http://web.default`，就會看到 nginx 的歡迎頁。

網址可以只寫 `http://<service 名稱>.<namespace>`；完整網域名稱（FQDN）請問管理者。

> 在終端機裡按住 `Ctrl` 點網址時，VSCodium 會問要不要開啟外部網站，但 預設版的映像檔裡沒有其他瀏覽器，所以按了也沒有反應。請照上面的步驟用 Integrated Browser 開。`-firefox` 版見第 5 節。

測完記得刪除：

```bash
kubectl -n default delete deploy/web svc/web
```

## 4. 使用時要知道的事

- **關掉 VSCodium 就登出**：按 `Ctrl+Q` 或右上角的關閉按鈕，遠端桌面隨即中斷。
- **斷線後無法接回原本的桌面**：重新連線一定會拿到新的 VSCodium，原本的桌面會在斷線 2 分鐘後關閉。尚未存檔的內容會遺失，請隨時存檔；已存檔的檔案在 `tkadm` 上，不受影響。
- **多人同時使用**：每次登入都有自己的桌面和 VSCodium，同一個帳號也可以同時登入兩次。同時最多 3 個桌面（所有帳號合計），超過時會看到 `Max session limit reached`。
- **換字型**：編輯器和終端機預設用 Cascadia Code，管理者可以改成其他字型。想自己換，按 `Ctrl+,` 搜尋 `font family`，在「Editor: Font Family」填字型名稱，例如 `'JetBrains Mono', 'Noto Sans Mono CJK TC'`；最後一個字型是用來顯示中文的。終端機沒有另外設定時會跟著用同一套字型。
- **設定會共用**：同一個帳號在不同桌面改的設定（例如字型大小）是同一份。管理者沒有設定保留資料時，系統重建後設定會回到預設值；有設定時會保留。
- **大家共用 tkadm 上的 bigred**：不同的 RDP 帳號連到 `tkadm` 後都是同一個使用者，彼此看得到、也改得到對方的檔案。
- **輸入中文**：遠端桌面裡沒有中文輸入法。在自己的電腦（例如記事本）打好，複製後在 VSCodium 按 `Ctrl+V` 貼上。
- **YAML 補全**：`tkadm` 第一次連線時會自動安裝 YAML 擴充功能（extension）。編輯 `.yaml` 檔時，按 `Ctrl+Space` 會出現 Kubernetes 欄位的建議。

## 5. `-firefox` 版（`:1.2-firefox`）

管理者部署的是 `-firefox` 版時：

- 在終端機按住 `Ctrl` 點網址，確認開啟後會用 Firefox 開，一樣可以用叢集內的網址。
- 按 `Alt+Tab` 在 VSCodium 和 Firefox 之間切換。
- 關掉 Firefox 不會登出；關掉 VSCodium 才會。

## 6. 常見問題

| 看到的訊息或現象 | 原因 | 處理 |
|---|---|---|
| 憑證警告「無法驗證此遠端電腦的身分識別」 | Pod 使用自己產生的憑證 | 按「是」繼續 |
| `User does not exist, or could not be authenticated` | RDP 帳號或密碼錯誤 | 向管理者確認帳密 |
| `Max session limit reached` | 已經有 3 個桌面在使用 | 等別人登出；剛斷線的桌面要 2 分鐘後才會釋放 |
| 一直跳出 tkadm 的密碼框 | 密碼錯誤，或 `tkadm` 的 sshd 不允許埠轉發 | 確認密碼；仍然不行請管理者檢查 `AllowTcpForwarding` |
| 登入後畫面閃一下就斷線 | Pod 的 `/dev/shm` 太小，VSCodium 啟動時崩潰 | 請管理者確認部署有掛 `/dev/shm`（見 [architecture.md](architecture.md) 的「其他連線」） |
| 重新連線後，原本開的檔案分頁不見了 | 每次連線都是新的桌面 | 從檔案總管重新開啟；檔案在 `tkadm` 上，不會遺失 |

> 本手冊的步驟已於 2026-10-28 在 tk8s 上，以 FreeRDP 模擬遠端桌面連線實測：xrdp 登入、輸入 tkadm 密碼後連線、在 tkadm 用 `kubectl` 部署 nginx、在 Pod 內用 FQDN 開啟、關掉 VSCodium 後登出、同一個帳號同時登入兩次、斷線後清除、stateful 模式在 Pod 重建後保留設定。尚未用實體 Windows 電腦實測；剪貼簿貼上中文、YAML 補全畫面、Firefox 版本的操作尚未實測。
