# VSCodium 遠端桌面使用手冊

適用映像檔：`ghcr.io/braveantony/rdp-vscode:1.0`（`:1.0-firefox` 另見第 5 節）。安裝方式見 [README](../README.zh-TW.md#快速開始)。

用 Windows 內建的「遠端桌面連線」登入後，畫面上只有一個全螢幕的 VSCodium。它會自動以 SSH 連到叢集的管理 Pod `tkadm`，你在 VSCodium 裡開的檔案和終端機都在 `tkadm` 上，可以直接用 `kubectl` 管理叢集。

## 1. 連線與登入

| 項目 | 值 |
|---|---|
| 電腦 | 管理者給你的位址，例如 `192.168.11.64:3390`（tk8s 經主機轉發），或 `<節點 IP>:30390` |
| 帳號 | 管理者發給你的帳號（預設是 `bigred`） |
| 密碼 | 管理者發給你的密碼（預設是 `bigred`） |

1. 按 `Win+R`，輸入 `mstsc`，按 Enter，開啟「遠端桌面連線」。
2. 電腦欄位填上面的位址（含 `:` 和埠號），按「連線」。
3. 出現憑證警告（「無法驗證此遠端電腦的身分識別」）時，按「是」。每個 Pod 使用自己產生的憑證，這是正常的。
4. 畫面會出現 xrdp 的登入畫面：Session 保持 `Xorg`，填入帳號和密碼，按 OK。

## 2. 連到 tkadm

1. 登入後畫面是全螢幕的 VSCodium，上方會跳出 `Enter password for bigred@tkadm.taroko`。
2. 輸入 `tkadm` 的密碼（預設是 `bigred`），按 Enter。
3. 左下角變成 `SSH: tkadm`，左邊的檔案總管列出 `tkadm` 上 `/home/bigred` 的檔案，就表示連上了。

- `tkadm` 上還沒有這個版本的 vscodium-server 時（第一次連線、`tkadm` 重建後，或升級映像檔後），`tkadm` 會先下載約 90MB，需要多等一段時間。
- 之後每次重新連線（包括「重新載入視窗」），都會再問一次密碼。
- 不小心按了取消時，按 `Ctrl+Shift+P`，執行「Developer: Reload Window」（重新載入視窗），密碼框會再出現一次。

## 3. 在 tkadm 部署網站並開啟

1. 按 `` Ctrl+` `` 開啟終端機。這個終端機在 `tkadm` 上執行。
2. 部署一個 nginx：

   ```bash
   kubectl create deploy web --image=nginx
   kubectl expose deploy web --port 80
   kubectl rollout status deploy/web
   ```

3. 按 `Ctrl+Shift+P`，輸入 `Open Integrated Browser`，選「Browser: Open Integrated Browser」；或按標題列右邊的地球圖示。
4. 在網址列輸入 `http://web.default.svc.tk8s.k8s`（或短名稱 `http://web.default`），就會看到 nginx 的歡迎頁。

網址的格式是 `http://<service 名稱>.<namespace>.svc.<cluster domain>`，也可以只寫短名稱 `http://<service 名稱>.<namespace>`。tk8s 的 cluster domain 是 `tk8s.k8s`，其他叢集通常是 `cluster.local`，可以在 `tkadm` 的終端機用 `kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep kubernetes` 查到。VSCodium 本身就在叢集裡，所以不需要 port-forward、NodePort 或 Ingress。

> 在終端機裡按 `Ctrl` 點網址，VSCodium 會問要不要開啟外部網站，但預設的映像檔裡沒有瀏覽器，所以不會有反應。請照上面的步驟用 Integrated Browser 開。Firefox 版本見第 5 節。

測完記得刪除：

```bash
kubectl delete deploy/web svc/web
```

## 4. 使用時要知道的事

- **關掉 VSCodium 就是登出。** 按 `Ctrl+Q` 或右上角的關閉，遠端桌面會隨即中斷。
- **斷線後無法接回原本的桌面。** 重新連線一定會拿到新的 VSCodium，原本的桌面在斷線 120 秒後被清除。尚未存檔的內容會遺失，請隨時存檔。檔案本身在 `tkadm` 上，不受影響。
- **多人同時使用：** 每條連線都有自己的桌面和 VSCodium，同一個帳號也可以同時登入兩次。同時最多 3 個桌面（所有帳號合計），超過時會看到 `Max session limit reached`。
- **設定會共用：** 同一個帳號在不同連線改的設定（例如字型大小）是同一份。管理者如果用 stateless 模式部署，Pod 重建後設定會回到預設值；stateful 模式則會保留。
- **大家共用 tkadm 上的 bigred：** 不同的 RDP 帳號連到 `tkadm` 後都是同一個使用者，會互相看到、改到對方的檔案。
- **輸入中文：** Pod 裡沒有中文輸入法。在自己的電腦（例如記事本）打好，複製後在 VSCodium 按 `Ctrl+V` 貼上。
- **YAML 補全：** `tkadm` 第一次連線時會自動安裝 YAML 擴充功能（extension）。編輯 `.yaml` 檔時，按 `Ctrl+Space` 會出現 Kubernetes 欄位的建議。

## 5. Firefox 版本（`:1.0-firefox`）

管理者部署的是 Firefox 版本時：

- 在終端機按 `Ctrl` 點網址，確認開啟後會用 Firefox 開，一樣可以用叢集內的網址。
- 按 `Alt+Tab` 在 VSCodium 和 Firefox 之間切換。
- 關掉 Firefox 不會登出；關掉 VSCodium 才會。

## 6. 常見問題

| 看到的訊息或現象 | 原因 | 處理 |
|---|---|---|
| 憑證警告「無法驗證此遠端電腦的身分識別」 | Pod 使用自己產生的憑證 | 按「是」繼續 |
| `User does not exist, or could not be authenticated` | RDP 帳號或密碼錯誤 | 向管理者確認帳密 |
| `Max session limit reached` | 已經有 3 個桌面在使用 | 等別人登出；剛斷線的桌面要 120 秒後才會釋放 |
| 一直跳出 tkadm 的密碼框 | 密碼錯誤，或 `tkadm` 的 sshd 不允許埠轉發 | 確認密碼；仍然不行請管理者檢查 `AllowTcpForwarding` |
| 登入後畫面閃一下就斷線 | Pod 的 `/dev/shm` 太小，VSCodium 啟動時崩潰 | 請管理者確認部署有掛 `/dev/shm`（見 [architecture.md](architecture.md) 的「其他連線」） |
| 重新連線後，原本開的檔案分頁不見了 | 每次連線都是新的桌面 | 從檔案總管重新開啟；檔案在 `tkadm` 上，不會遺失 |

> 本手冊的步驟已於 2026-10-28 在 tk8s 上，以 FreeRDP 模擬遠端桌面連線實測：xrdp 登入、輸入 tkadm 密碼後連線、在 tkadm 用 `kubectl` 部署 nginx、在 Pod 內用 FQDN 開啟、關掉 VSCodium 後登出、同一個帳號同時登入兩次、斷線後清除、stateful 模式在 Pod 重啟後保留設定。尚未用實體 Windows 電腦實測；剪貼簿貼上中文、YAML 補全畫面、Firefox 版本的操作尚未實測。
