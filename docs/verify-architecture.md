# 驗證架構圖

本文件逐項對照[架構圖](architecture.md)和實際執行中的部署，確認圖上畫的元件、連線和設定都存在。**請由上到下，把每個指令區塊依序貼到終端機執行**，再和「應該看到」比較。所有指令都只讀取資料，不會修改叢集。

最後一節的腳本 `test/deploy/architecture.test.sh` 會一次跑完所有檢查。

![rdp-vscode 系統運作架構](architecture/rdp-vscode-architecture.png)

## 開始之前

需要先準備：

- 已經部署好 rdp-vscode（見[安裝手冊](install.md)），而且 namespace `taroko` 裡有 tkadm。
- 一台已安裝 `kubectl`、而且連得到這個叢集的電腦，通常就是安裝時用的那台。除了第 1 節最後一個指令要在 Windows 上執行，其他指令都在這台電腦執行。
- kubeconfig 要有 `kubectl exec` 的權限。這份文件大部分的指令都用 `kubectl exec`（在 Pod 裡執行指令，結果印回你的終端機）；README 列的安裝權限不包含它，但安裝時用的管理者 kubeconfig 通常都有。

在這台電腦下載 repo，之後的指令都在這個目錄執行（第 2 節和最後一節會讀 repo 裡的檔案）：

```bash
git clone https://github.com/braveantony/rdp-vscode.git
cd rdp-vscode
```

第 6 節和第 7 節的最後一項（③ vscodium-server）要檢查登入後才會出現的程式（process）。請先用遠端桌面登入，並在 VSCodium 輸入 tkadm 的 SSH 密碼（和遠端桌面的密碼是不同的兩組），連上 tkadm 後保持連線。

確認部署存在：

```bash
kubectl -n rdp-vscode get deploy,svc,pod
```

應該看到 `deployment.apps/rdp-vscode` 的 `READY` 是 `1/1`，Pod 是 `Running`。

## 1. RDP 入口：NodePort 與 Service（粗藍線上半段）

圖上畫的是：用戶端連到節點的 NodePort `30390`，再由 Service `rdp-vscode` 轉到 Pod 的 `3389` 埠。

```bash
kubectl -n rdp-vscode get svc rdp-vscode \
  -o jsonpath='{.spec.type} {.spec.ports[0].nodePort} -> {.spec.ports[0].targetPort}{"\n"}'
kubectl -n rdp-vscode get deploy rdp-vscode \
  -o jsonpath='{.spec.template.spec.containers[0].ports[0].name} {.spec.template.spec.containers[0].ports[0].containerPort}{"\n"}'
```

應該看到：

```text
NodePort 30390 -> rdp
rdp 3389
```

第一行表示 Service 是 NodePort，節點的 `30390` 埠轉到 Pod 上名稱為 `rdp` 的埠；第二行表示 container 的 `rdp` 埠就是 `3389`。

下面兩個指令印出的 IP 要相同，表示 Service 轉送的目標就是這個 Pod。第一個指令讀的是 EndpointSlice（Kubernetes 記錄 Service 實際轉送到哪些 Pod IP 的清單）：

```bash
kubectl -n rdp-vscode get endpointslice -l kubernetes.io/service-name=rdp-vscode \
  -o jsonpath='{.items[*].endpoints[*].addresses[0]}{"\n"}'
kubectl -n rdp-vscode get pod -l app=rdp-vscode -o jsonpath='{.items[0].status.podIP}{"\n"}'
```

最後，在要連線的 Windows 電腦開啟 PowerShell 執行（`<節點 IP>` 換成任一節點的 IP，可以用 `kubectl get nodes -o wide` 的 `INTERNAL-IP` 欄查看）：

```powershell
Test-NetConnection <節點 IP> -Port 30390
```

`TcpTestSucceeded` 應該是 `True`。節點在內部網段、要經過主機轉發時（見[安裝手冊的「從區網連線」](install.md#從區網連線節點在內部網段時)），改測實際連的位址，例如 `Test-NetConnection 192.168.11.64 -Port 3390`。

## 2. Pod 只有一個 container `desktop`（虛線框）

```bash
kubectl -n rdp-vscode get deploy rdp-vscode \
  -o jsonpath='{.spec.template.spec.containers[*].name} {.spec.template.spec.containers[0].image}{"\n"}'
cat VERSION
```

container 應該只有一個，名稱是 `desktop`；映像檔是 `ghcr.io/braveantony/rdp-vscode:<版本>`，版本和 repo 裡 `VERSION` 的內容相同。如果不同，表示部署的版本和這份架構圖不一致。

## 3. 帳號與設定（金線）

**Secret** 以唯讀方式掛載到 `/etc/rdp-vscode/users`；**ConfigMap `rdp-vscode-ssh`** 是選用的（`optional: true`，沒有建立這個 ConfigMap 也能啟動）：

```bash
kubectl -n rdp-vscode get deploy rdp-vscode -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{"\t"}{.secret.secretName}{.configMap.name}{"\t"}{.configMap.optional}{"\n"}{end}'
kubectl -n rdp-vscode get deploy rdp-vscode -o jsonpath='{range .spec.template.spec.containers[0].volumeMounts[*]}{.name}{"\t"}{.mountPath}{"\t"}{.readOnly}{"\n"}{end}'
```

應該看到：

- `users` 對應 `rdp-vscode-users-<雜湊>`，`readOnly` 是 `true`，掛在 `/etc/rdp-vscode/users`。
- `ssh-config` 對應 `rdp-vscode-ssh`，`optional` 是 `true`，掛在 `/etc/rdp-vscode/ssh`。

另外兩行 `home`、`dshm` 後面是空的，因為它們不是 Secret 或 ConfigMap，第 4 節再檢查。

圖上的金線「帳號」：`entrypoint.sh` 啟動時依 Secret 建立帳號，並把帳號名稱寫進 log：

```bash
kubectl -n rdp-vscode logs deploy/rdp-vscode | grep '\[entrypoint\] accounts'
```

應該看到 `[entrypoint] accounts:`，後面是帳號清單裡的帳號，例如 `[entrypoint] accounts: bigred`。

`entrypoint.sh` 寫出的 SSH 設定：預設依 `SSH_*` 環境變數產生；掛了內容不是空的 ConfigMap 時，就是 ConfigMap 的內容。

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- cat /etc/ssh/ssh_config.d/rdp-vscode.conf
```

應該看到你設定的 SSH 目標。預設是 `Host tkadm`、`HostName tkadm.taroko`、`Port 22100`。

## 4. 儲存：`/home` 與 `/dev/shm`（底部兩個 volume）

```bash
kubectl -n rdp-vscode get deploy rdp-vscode -o jsonpath='{range .spec.template.spec.volumes[?(@.name=="home")]}home: emptyDir={.emptyDir} pvc={.persistentVolumeClaim.claimName}{"\n"}{end}{range .spec.template.spec.volumes[?(@.name=="dshm")]}dshm: {.emptyDir.medium} {.emptyDir.sizeLimit}{"\n"}{end}'
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- df -h /dev/shm
```

應該看到：

- `home`：stateless 模式是 `emptyDir={}`（emptyDir 是 Pod 刪掉就跟著消失的暫存空間），stateful 模式是 `pvc=rdp-vscode-home`（PVC 是向叢集申請的永久儲存空間）。
- `dshm`：`Memory 1Gi`。
- 第二個指令的 `Size` 是 `1.0G`，表示 Pod 裡的 `/dev/shm` 真的是 1 GiB。

## 5. ① xrdp `:3389`／xrdp-sesman

圖上的 ① 是 xrdp 和 xrdp-sesman。依[架構說明](architecture.md)，container 啟動時由 tini 執行 `entrypoint.sh`，再由它啟動這兩個程式，都以 root 執行。

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- ps -eo pid,ppid,user,args
```

應該看到類似這樣的輸出：

```text
    PID    PPID USER     COMMAND
      1       0 root     /usr/bin/tini -- /opt/rdp-vscode/entrypoint.sh
      2       1 root     bash /opt/rdp-vscode/entrypoint.sh
     40       2 root     xrdp-sesman --nodaemon
     41       2 root     xrdp --nodaemon
```

PID 1 是 tini；`entrypoint.sh` 的 PPID（父程式的 PID，也就是誰啟動了它）是 1；xrdp 和 xrdp-sesman 的 PPID 是 `entrypoint.sh` 的 PID。有人登入時，清單裡還會有各桌面的程式（見第 6 節）。

## 6. ② Xorg session × N 與全螢幕 VSCodium

VSCodium 方塊裡的 Open Remote-SSH 和繁中語言包預先放在映像檔裡，每次登入時安裝。這一項不用登入：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- ls /opt/rdp-vscode/vsix
```

應該看到 `jeanp413.open-remote-ssh-<版本>.vsix` 和 `ms-ceintl.vscode-language-pack-zh-hant-<版本>.vsix`。

以下**需要有人登入**。每個桌面在 `/tmp/sess/` 下有一個 `<display>.<uid>` 目錄：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- ls /tmp/sess
```

應該列出類似 `10.1000` 的目錄：display 10（X 的顯示編號，xrdp 從 10 開始編）、UID 1000（Linux 的使用者編號，帳號清單裡的第一個帳號是 1000，第二個是 1001，依此類推）。

下面的指令把 `1000` 換成上一個指令看到的 UID（`.` 後面的數字），`10` 換成 display（`.` 前面的數字）：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- ps -u 1000 -o comm= | sort | uniq -c
```

輸出應該包含 `Xorg`、`openbox` 和 `codium`。

VSCodium 一啟動就自動連到 tkadm：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- \
  sh -c 'ps -u 1000 -o args= | grep "^/usr/share/codium/codium " | grep -v -- --type='
```

應該看到 `--user-data-dir=/tmp/sess/10.1000/data` 和 `--remote=ssh-remote+tkadm /home/bigred`。

## 7. 以 SSH 連到 tkadm 與 ③ vscodium-server（綠線）

tkadm 的 Service 開著 `22100` 埠，rdp-vscode 的 Pod 連得到它，而且回應的是 SSH 伺服器：

```bash
kubectl -n taroko get svc tkadm
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- \
  timeout 5 bash -c 'exec 3<>/dev/tcp/tkadm.taroko/22100; head -c 7 <&3; echo'
```

第一個指令的 `PORT(S)` 欄要有 `22100`，例如 `22100:32200/TCP`；第二個指令應該印出 `SSH-2.0`。

tkadm 的 sshd（SSH 伺服器程式）允許本機埠轉發（讓 SSH 連線順便轉送其他連線，VSCodium 靠它連到 ③）：

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- /usr/sbin/sshd -T | grep allowtcpforwarding
```

應該是 `allowtcpforwarding local`（或 `yes`）。

**需要有人登入，而且已經在 VSCodium 輸入 tkadm 的 SSH 密碼。** 先確認 Pod 現在連著 tkadm 的 22100 埠（`5654` 是 22100 的 16 進位，`01` 表示連線中）：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- \
  sh -c 'cat /proc/net/tcp /proc/net/tcp6 | awk "\$3 ~ /:5654\$/ && \$4 == \"01\"" | wc -l'
```

應該印出 `1` 以上的數字，每個連著 tkadm 的桌面一條連線。

③ vscodium-server 在 tkadm 上執行，不在 rdp-vscode 的 Pod 裡：

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- sh -c 'ps -eo user,args | grep "[.]vscodium-server" | cut -c1-120'
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- sh -c 'ps -eo args | grep "[.]vscodium-server" || echo none'
```

第一個指令應該列出幾個 `~/.vscodium-server/bin/<commit>/node` 程式；第二個指令應該印出 `none`。連線結束後，vscodium-server 還會在 tkadm 上留一段時間才自動關閉，所以沒人連線時也可能看得到它；要確認「現在」連著，看的是上一個指令的連線數。

## 8. Integrated Browser 與 kubectl（橙線）

Integrated Browser 在 Pod 裡執行，所以 Pod 要能用 `<service>.<namespace>` 解析並連到叢集內的 Service。這裡用每個叢集都有的 `kubernetes.default`（namespace `default` 裡的 Kubernetes API Service）測試：

```bash
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- getent hosts kubernetes.default
kubectl -n rdp-vscode exec deploy/rdp-vscode -c desktop -- \
  timeout 5 bash -c 'exec 3<>/dev/tcp/kubernetes.default/443 && echo connected'
```

第一個指令應該印出一個 ClusterIP（Service 在叢集內的虛擬 IP），第二個指令應該印出 `connected`。

tkadm 上的 kubectl 連得到 Kubernetes API：

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- kubectl version
```

應該有 `Server Version:` 這一行。

## 一次跑完所有檢查

在剛才下載的 `rdp-vscode` 目錄執行：

```bash
bash test/deploy/architecture.test.sh
```

腳本依上面第 1～8 節的順序檢查（第 1 節的 Windows 指令除外），每一項印出 `PASS`、`FAIL` 或 `SKIP`。倒數第二行是跳過的項數（`N skipped`），最後一行應該是 `N passed, 0 failed`。

- 沒有人登入，或還沒連上 tkadm 時，第 6、7 節需要登入的項目會顯示 `SKIP`，登入並連上後再跑一次即可。
- SSH 目標依 Deployment 的 `SSH_*` 環境變數或 ConfigMap 判斷，改過 SSH 設定也能檢查。
- rdp-vscode 或 tkadm 部署在其他 namespace 時，用 `NS=<namespace>`、`TKADM_NS=<namespace>` 指定。

| 結果 | 說明 |
|---|---|
| `FAIL image` | 部署的映像檔版本和 repo 的 `VERSION` 不同，架構圖描述的是 `VERSION` 那一版 |
| `FAIL ... AllowTcpForwarding` | tkadm 的 sshd 不允許埠轉發，見 [ops/2026-10-27-tkadm-sshd-forwarding.md](ops/2026-10-27-tkadm-sshd-forwarding.md) |
| `SKIP` | 還沒有人登入，或還沒連上 tkadm；登入並連上後再跑一次 |
| `NOTE /tmp/sess has leftover dirs` | 有桌面異常結束、目錄沒清掉；不影響使用，Pod 重啟時會清除 |
