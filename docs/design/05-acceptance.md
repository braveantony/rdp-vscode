# 05 驗收標準

在 tk8s 上實際驗證。「自動」的部分由 `test/e2e/run.sh` 執行；「手動」的部分列在 `test/e2e/manual-checklist.md`，需要人看畫面確認。

## 10 項驗收標準

| # | 驗收項目 | 自動驗證 | 手動確認 |
|---|---|---|---|
| AC1 | `kubectl apply -k manifests/stateless` 後，pod 會 Ready | `kubectl wait` 180 秒內 Ready | — |
| AC2 | 用 RDP 連 `<節點 IP>:30390`，以 bigred/bigred 登入 | FreeRDP 登入後，pod 裡出現 bigred 的 Xorg | — |
| AC3 | 畫面是全螢幕 VSCodium，自動跳出 tkadm 密碼框；輸入密碼後，左下角顯示 `SSH: tkadm` | codium 的啟動參數包含 `ssh-remote+tkadm`；輸入密碼後，tkadm 上出現**比 marker 檔新**的 server 檔案 | 畫面和左下角的連線狀態 |
| AC4 | 在 VSCodium terminal（tkadm 上）部署 nginx | `kubectl create deploy web` 和 `expose` 成功 | 在 VSCodium 裡實際操作 |
| AC5 | 用 Integrated Browser 打開 `http://web.default.svc.tk8s.k8s`，看到 nginx 歡迎頁（原本是 Simple Browser，見 01 的「實作後的修正」） | 在 pod 內 `curl` 這個 FQDN，回應含 `Welcome to nginx` | Integrated Browser 的畫面 |
| AC6 | YAML 檔有 Kubernetes schema 補全 | tkadm 上有安裝 `redhat.vscode-yaml` | 實際打字時出現補全 |
| AC7 | 關掉 VSCodium，RDP session 跟著結束 | Xorg 消失，session 目錄被清掉 | — |
| AC8 | Stateful：改一個設定、刪掉 pod、重新連線後設定還在 | pod 重建後**重新登入**，新 session 讀到的設定值仍然正確 | 畫面上的字型大小真的有改變 |
| AC9 | （已移除：`-firefox` 版在 2026-10-29 拿掉） | — | — |
| AC10 | `VSCODIUM_LOCALE=en` 時介面是英文 | codium 的啟動參數包含 `--locale en` | 截圖確認 |

## 額外檢查（Review Focus）

這些情境不在 10 項驗收標準裡，但最容易在實際使用時出問題，所以也列為必測：

| 情境 | 預期行為 | 在哪裡測 |
|---|---|---|
| 同一個帳號同時登入兩次 | 兩個 VSCodium 各自獨立，第二個視窗不會跑到第一個人的畫面 | Task 4 |
| Stateful 模式下調換 `users.txt` 的順序 | 帳號 UID 改變，但 home 的擁有者跟著修正，仍然可以正常登入 | Task 3 |
| ConfigMap 存在但內容是空的 | 退回使用環境變數產生的設定 | Task 1 |
| RDP 斷線但沒有關閉 VSCodium | 150 秒內 Electron 程序全部結束，不殘留記憶體 | Task 4 |
| tkadm 連不上或密碼打錯 | VSCodium 顯示錯誤，但 RDP session **不會**登出，可以重試 | Task 7 |

## 驗證時的注意事項

- **不可以刪除 tkadm 上的 `~/.vscodium-server`**：tkadm 是共用的，刪掉會影響其他正在用的人。判斷是不是這次連線產生的，改用 marker 檔加上 `find -newer`
- 測試建立的容器、volume、port-forward，一律用固定名稱，並在測試結束時清除，避免佔住 port 影響其他測試
- 從 host 連不到 tkadm 的 NodePort（32200），但連得到 ClusterIP。所以本機的 podman 測試是透過叢集 DNS（`--dns 10.98.0.10 --dns-search svc.tk8s.k8s`）連到 `tkadm.taroko:22100`
