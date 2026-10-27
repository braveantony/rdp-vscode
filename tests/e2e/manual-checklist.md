# 手動驗收清單

`tests/e2e/run.sh` 已經自動驗證了每一項可以用程式檢查的部分。以下是只能用眼睛確認的部分，請在真實的 RDP client（Windows 遠端桌面、Remmina 等）上操作。

## 準備

```bash
kubectl apply -k deploy/stateless        # AC8 改用 deploy/stateful
kubectl -n rdp-vscode wait --for=condition=Ready pod -l app=rdp-vscode --timeout=180s
```

RDP 連到 `<節點 IP>:30390`，在 xrdp 登入畫面輸入 `bigred` / `bigred`。

## AC3：全螢幕 VSCodium，自動連到 tkadm

- [ ] 畫面是全螢幕的 VSCodium，沒有視窗邊框，介面是繁體中文
- [ ] 上方自動跳出 `Enter password for bigred@tkadm.taroko`
- [ ] 輸入 `bigred` 後，左下角顯示 `SSH: tkadm`，檔案總管列出 tkadm 上 `/home/bigred` 的內容

## AC4、AC5：部署網站，用 FQDN 開啟

- [ ] 在 VSCodium 開啟 terminal（`` Ctrl+` ``），執行：
  ```bash
  kubectl create deploy web --image=nginx && kubectl expose deploy web --port 80
  ```
- [ ] 按 `Ctrl+Shift+P`，執行 `Browser: Open Integrated Browser`（或按標題列右邊的地球圖示），輸入 `http://web.default.svc.tk8s.k8s`，看到 nginx 的歡迎頁
- [ ] 測完執行 `kubectl delete deploy/web svc/web`

> 原本的設計是 Simple Browser，但它只能開 `localhost` 這類網址（Task 0 第 5 題），所以改用 VSCodium 內建的 Integrated Browser。

## AC6：YAML 的 Kubernetes schema 補全

- [ ] 在 tkadm 上新增 `test.yaml`，輸入 `apiVersion: apps/v1`、`kind: Deployment` 後，`spec:` 底下按 `Ctrl+Space` 會出現 `replicas`、`selector`、`template` 等欄位建議
- [ ] 欄位打錯（例如 `replica:`）時，會出現波浪底線

## AC7：關掉 VSCodium 就登出

- [ ] 按 `Ctrl+Q` 或視窗右上角的關閉，RDP 連線隨即結束

## AC8：Stateful 模式的設定保留（畫面確認）

- [ ] 用 `deploy/stateful` 部署，登入後按 `Ctrl+,` 把「Editor: Font Size」改成 `20`
- [ ] 執行 `kubectl -n rdp-vscode delete pod -l app=rdp-vscode`，等新 pod Ready 後重新連線
- [ ] 編輯器的字型仍然是放大後的大小

## AC9：`-firefox` 版本

用 `localhost/rdp-vscode:dev-firefox`（或 `ghcr.io/braveantony/rdp-vscode:1.0-firefox`）部署：

- [ ] 在 VSCodium terminal 執行 `echo http://web.default.svc.tk8s.k8s`，用 `Ctrl+` 點擊網址，確認對話框後會開啟 Firefox，並顯示 nginx 歡迎頁
- [ ] `Alt+Tab` 可以在 VSCodium 和 Firefox 之間切換
- [ ] 關掉 Firefox 不會結束 session；關掉 VSCodium 才會

## AC10：英文介面

- [ ] `kubectl -n rdp-vscode set env deploy/rdp-vscode VSCODIUM_LOCALE=en`，重新連線後介面是英文
