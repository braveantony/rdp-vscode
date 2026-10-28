# rdp-vscode

[English](README.md)

> **安全警告**：預設帳號 `bigred` / `bigred` 只適合隔離的實驗叢集。只要能連到 NodePort 30390，用這組帳密就能進到叢集內部網路，接著 SSH 到 `tkadm`，再用 `tkadm` 上的 `kubectl` 控制整個叢集。部署到其他環境之前，請先修改 `deploy/*/users.txt` 裡的密碼。

用任何 RDP 用戶端（Windows 遠端桌面連線、Remmina、FreeRDP）登入，畫面就是一個在 Kubernetes 叢集裡執行的全螢幕 [VSCodium](https://vscodium.com/)。登入後，它會用 [Open Remote-SSH](https://open-vsx.org/extension/jeanp413/open-remote-ssh) 自動 SSH 到叢集的管理 Pod（預設是 `tkadm`），你編輯的檔案、執行的 `kubectl` 都在那台上。因為編輯器本身就在叢集裡，可以直接用 Service 的 DNS 名稱開網站，例如 `http://web.default.svc.cluster.local`，不需要 port-forward 或 Ingress。

```text
RDP 用戶端 ──> NodePort 30390 ──> rdp-vscode Pod
                                   ├─ xrdp：每條 RDP 連線各自一個 Xorg
                                   └─ VSCodium（全螢幕，openbox）──SSH 22100──> tkadm Pod（kubectl）
                                         └─ Integrated Browser ──> http://<svc>.<ns>.svc.<cluster-domain>
```

## 快速開始

需要先準備：

- 一個可以 `kubectl apply` 的 Kubernetes 叢集。
- 一台 VSCodium 連得到的 SSH 目標。預設是 `tkadm.taroko:22100`，帳號 `bigred`。它的 sshd 必須允許本機埠轉發（`AllowTcpForwarding local` 或 `yes`），因為 Open Remote-SSH 要透過轉發連到遠端的 server。Alpine 的 openssh 預設是 `AllowTcpForwarding no`。

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
kubectl apply -k deploy/stateless
kubectl -n rdp-vscode rollout status deploy/rdp-vscode
kubectl get nodes -o wide        # 任一節點的 INTERNAL-IP
```

RDP 用戶端連到 `<節點 IP>:30390`。在 xrdp 登入畫面，Session 保持 `Xorg`，用 `bigred` / `bigred` 登入。VSCodium 會要你輸入 `tkadm` 的 SSH 密碼（`bigred`）。操作方式見[使用手冊](user-guide.md)。

## Stateless 和 stateful

| Overlay | `/home` | Pod 重啟時 |
|---|---|---|
| `deploy/stateless` | `emptyDir` | 檔案、設定和自己裝的 extension 都會消失 |
| `deploy/stateful` | PVC `rdp-vscode-home`，5Gi，ReadWriteOnce | `/home` 底下的東西都會保留 |

stateful 的 PVC 沒有指定 `storageClassName`，會使用叢集預設的 StorageClass。這個 StorageClass 必須在第一次使用時才綁定（`volumeBindingMode: WaitForFirstConsumer`，`local-path` 本來就應該這樣設定），或是網路儲存。如果是 `Immediate`，像 `local-path` 這種建在節點本機上的儲存，不知道要在哪一台節點建立 volume，PVC 會一直 `Pending`，事件顯示 `no node was specified`。另外，`local-path` 的 volume 只存在一台節點上，那台節點故障時，Pod 就起不來。

`deploy/example/ssh-configmap` 示範怎麼用自己的檔案取代自動產生的 SSH 設定。

## 帳號

`deploy/*/users.txt` 一行一個 `帳號:密碼`，會產生 Secret `rdp-vscode-users`。帳號依檔案順序分配 UID 1000、1001……，各自有權限 `0700` 的 home。在 stateful 部署中調換順序時，啟動時會把既有的 home 交給新的 UID；被移除帳號的 home 會改成 root 擁有，拿到它舊 UID 的帳號讀不到。檔案在 Windows 上編輯（CRLF 換行）也沒關係。所有帳號在 `tkadm` 上都用同一個 SSH 帳號登入。

可以多人同時登入，同一個帳號也可以同時登入兩次，上限是 `MAX_SESSIONS`。每條 RDP 連線都有自己的桌面和自己的 VSCodium；同一個帳號的 `~/.config/VSCodium/User` 設定是共用的。斷線後無法接回原本的桌面，它會在 120 秒後被清除。關掉 VSCodium 就會登出。

## 設定

在 Deployment（`deploy/base/deployment.yaml`）設定這些環境變數：

| 變數 | 預設值 | 說明 |
|---|---|---|
| `MAX_SESSIONS` | `3` | 同時連線上限（所有帳號合計） |
| `SSH_HOST_ALIAS` | `tkadm` | 登入時 VSCodium 自動連線的 SSH `Host` 名稱；設成空字串就不自動連線 |
| `SSH_HOST` | `tkadm.taroko` | SSH 目標的主機名稱或 IP |
| `SSH_PORT` | `22100` | SSH 埠 |
| `SSH_USER` | `bigred` | SSH 帳號 |
| `SSH_REMOTE_FOLDER` | `/home/bigred` | 連線後在 SSH 目標上開啟的資料夾 |
| `VSCODIUM_LOCALE` | `zh-tw` | 介面語言：`zh-tw` 或 `en` |

產生的 SSH 設定會寫到 `/etc/ssh/ssh_config.d/rdp-vscode.conf`。如果有內容不是空的 ConfigMap `rdp-vscode-ssh`（key `config`），就整份改用它。

**叢集內的 DNS 名稱**：`SSH_HOST` 用的是短名稱 `tkadm.taroko`（`<service>.<namespace>`），任何 cluster domain 都能用。開網站時可以用短名稱，也可以用完整的 `<svc>.<ns>.svc.<cluster-domain>`。cluster domain 不一定是 `cluster.local`（tk8s 是 `tk8s.k8s`），可以這樣查：

```bash
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep kubernetes
```

## 資源

requests 是 CPU `500m`、記憶體 `1Gi`；limits 是 CPU `4`、記憶體 `4Gi`，以 3 個 session 估算。每多一個 session 約多需要 1Gi。Pod 超過記憶體上限時會被 OOM kill，所有 session 一起中斷。`/dev/shm` 是 1Gi 的記憶體 `emptyDir`，因為用預設的 64MiB 時，VSCodium 載入中文字型會崩潰。

## 映像檔

| Tag | 內容 | 大小 |
|---|---|---|
| `ghcr.io/braveantony/rdp-vscode:1.0` | VSCodium 1.143.17183、Open Remote-SSH 0.5.1、繁體中文語言包 1.131.0 | 約 1.3GB |
| `ghcr.io/braveantony/rdp-vscode:1.0-firefox` | 以上再加上 Firefox ESR，並設為預設瀏覽器 | 約 1.6GB |

自己建置的方法見 [build-image.md](build-image.md)。

## 已知限制

- 所有 RDP 帳號都用同一個帳號登入 `tkadm`，會共用那裡的檔案和 `kubectl` 權限。
- `tkadm` 上的 `~/.vscodium-server` 沒有持久化，`tkadm` 重啟後第一次連線會重新下載 server（約 90MB）。
- 只能用 [Open VSX](https://open-vsx.org/) 上的 extension，Pylance、C# Dev Kit、Copilot 這類微軟專屬的 extension 不能用。
- 每次重新連線，包括 `Reload Window`，Open Remote-SSH 都會再問一次 SSH 密碼。
- 點連結不會自動用內建瀏覽器開啟，要自己開 Integrated Browser（`Browser: Open Integrated Browser`）。
- 不能在 Pod 裡直接打中文，要在自己的電腦打好再貼上。
- xrdp 的監聽程式以 root 執行，因為 Debian trixie 的 xrdp 0.10.1 不支援降權。

## 授權

[Apache-2.0](LICENSE)
