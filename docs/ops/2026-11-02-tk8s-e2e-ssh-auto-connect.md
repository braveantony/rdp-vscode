# 2026-11-02 在 tk8s 上驗證 `SSH_AUTO_CONNECT`：刪除原本的 rdp-vscode 部署

## 為什麼要改

`feat/ssh-auto-connect` 分支新增 `SSH_AUTO_CONNECT`（預設 `false`）。合併前在 tk8s 上跑 `test/e2e/run.sh` 和 `test/deploy/architecture.test.sh`，確認 `false` 和 `true` 兩種情況在叢集上都正常。`run.sh` 開始時會刪掉 namespace `rdp-vscode` 再重新部署，所以原本的部署會被拿掉。這次用 `E2E_KEEP=1` 執行，`run.sh` 結束時不刪 namespace，測完後再手動刪除。

## 修改前的狀態

- namespace `rdp-vscode`：stateless 部署，映像檔 `ghcr.io/braveantony/rdp-vscode:1.1`，已執行約 4 天 16 小時，測試前沒有人連線。
- `/home` 是 emptyDir，bigred 的家目錄約 6.9 MB。

## 做了什麼

1. 用分支上的 commit `c1af37c` 建置 `localhost/rdp-vscode:dev`，載入 `tk8s-worker-1` 和 `tk8s-worker-2`。
2. 以 `E2E_KEEP=1` 執行 `test/e2e/run.sh all`，22 項通過。這一輪會用 `kubectl set env` 把 `SSH_AUTO_CONNECT` 設成 `true`。
3. 用預設值（`false`）部署 stateless，執行三輪 `architecture.test.sh`：登入後還沒連線、手動連上 tkadm、切成 `true`。三輪都只有映像檔版本那 1 項失敗，因為測試要求 `ghcr.io/braveantony/rdp-vscode:1.3`，這次部署的是 `localhost/rdp-vscode:dev`；其餘都通過。
4. 測試過程中在 namespace `default` 建立、再刪除 Service `web`。
5. 測完後手動 `kubectl delete ns rdp-vscode`。

### 載入映像檔失敗的處理

`run.sh` 第 66 行把 podman 的 runroot 寫死成 `/run/rdp-vscode-load-<node>`。兩台 worker 的 storage 資料庫當初是用 `/run/ffw-load-<node>` 建立的（應該是別的專案留下的），podman 回報 `database configuration mismatch`，Pod 卡在 `ImagePullBackOff`。這次在 repo 外複製一份 `run.sh`，只把 runroot 改成 `/run/ffw-load-<node>` 後重跑；repo 裡的 `run.sh` 還沒修。

## 修改後的狀態

- namespace `rdp-vscode` 已刪除，原本的 `1.1` 部署和 bigred 的家目錄都不在了。
- `default` 的 `web` 已刪除，tkadm 上的測試 marker 檔已刪除。
- 兩台 worker 上留著 `localhost/rdp-vscode:dev`（映像檔 ID `22ca56f`）。
- tkadm 上 bigred 的 `~/.vscodium-server` 有這次連線產生的檔案。

## 如何還原

家目錄的內容無法還原。重新部署：

```bash
curl -fsSL https://raw.githubusercontent.com/braveantony/rdp-vscode/main/install.sh | bash
```

清掉節點上的測試映像檔：

```bash
for n in tk8s-worker-1 tk8s-worker-2; do sudo podman exec $n crictl rmi localhost/rdp-vscode:dev; done
```
