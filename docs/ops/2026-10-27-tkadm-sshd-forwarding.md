# 2026-10-27 修改 tkadm sshd：開啟 `AllowTcpForwarding local`

## 為什麼要改

Task 0 第 3 題發現：Open Remote-SSH 必須透過 SSH 轉發連到 tkadm 上的 vscodium-server，但 tkadm 的 sshd 是 `AllowTcpForwarding no`（Alpine openssh 套件的預設值，寫在 `/etc/ssh/sshd_config` 第 92 行）。這個設定會讓 TCP 轉發和 Unix socket 轉發（`direct-streamlocal`）都失敗。

決定（推翻 D4「不修改 tkadm」）：把 tkadm 改成 `AllowTcpForwarding local`。只允許 local forwarding（`ssh -L`），remote forwarding（`ssh -R`）仍然關閉。

做法：用 ConfigMap 掛一個設定檔到 `/etc/ssh/sshd_config.d/`，不重新 build image。tkadm 的 `sshd_config` 第 15 行是 `Include /etc/ssh/sshd_config.d/*.conf`，位置在第 92 行之前。sshd 採用「第一個出現的設定生效」，所以這個檔案會覆蓋原本的 `no`。

## 修改前的狀態

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- sh -c \
  'grep -n -i -E "^(Include|AllowTcpForwarding|AllowStreamLocal)" /etc/ssh/sshd_config;
   /usr/sbin/sshd -T | grep -E "allowtcpforwarding|allowstreamlocalforwarding"'
```

```
15:Include /etc/ssh/sshd_config.d/*.conf
92:AllowTcpForwarding no
allowtcpforwarding no
allowstreamlocalforwarding yes
```

- Pod：`tkadm-5df94d7566-7q7lk`（已執行 27 小時）
- `/etc/ssh/sshd_config.d/` 原本是空的
- 修改前的 deployment 已備份到 session scratchpad 的 `tkadm-deploy-before.yaml`（暫存，不保留）

## 注意：manifest 是範本，不能直接 apply

`~/tk/wulin/wk/tkadm/tkadm-dkreg.yaml` 的 DNS search 寫的是 `svc.k1.k8s`，叢集上實際是 `svc.tk8s.k8s`。直接 `kubectl apply -f` 會把 tkadm 的 DNS 設定改壞，所以這次是用 `kubectl patch` 修改叢集上的 deployment，範本檔另外修改。

## 執行的命令

### 1. 建立 ConfigMap

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: tkadm-sshd-rdp-vscode
  namespace: taroko
  labels:
    app: tkadm
data:
  rdp-vscode.conf: |
    # Required by rdp-vscode (Open Remote-SSH tunnels to vscodium-server)
    AllowTcpForwarding local
EOF
```

### 2. Patch tkadm deployment（只加 volume 和 mount）

```bash
kubectl -n taroko patch deployment tkadm --type=json -p='[
 {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"sshd-rdp-vscode","configMap":{"name":"tkadm-sshd-rdp-vscode"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"sshd-rdp-vscode","mountPath":"/etc/ssh/sshd_config.d/rdp-vscode.conf","subPath":"rdp-vscode.conf","readOnly":true}}
]'
kubectl -n taroko rollout status deployment/tkadm --timeout=180s
```

`containers/0` 是 `tkadm` container（`containers/1` 是 `dkreg`）。tkadm pod 重啟，同一個 pod 裡的 dkreg 也跟著重啟。

### 3. 修改範本檔

```bash
cd ~/tk/wulin/wk/tkadm
cp -p tkadm-dkreg.yaml tkadm-dkreg.yaml.bak
# 在 Deployment 前加入同樣的 ConfigMap，並在 volumes / tkadm container 的 volumeMounts 最後加上：
#   - name: sshd-rdp-vscode
#     configMap:
#       name: tkadm-sshd-rdp-vscode
#   - name: sshd-rdp-vscode
#     mountPath: /etc/ssh/sshd_config.d/rdp-vscode.conf
#     subPath: rdp-vscode.conf
#     readOnly: true
```

確認範本檔（換掉網域後）跟叢集上的狀態一致：

```bash
sed 's/k1\.k8s/tk8s.k8s/g' tkadm-dkreg.yaml | kubectl diff -f -   # 沒有輸出，rc=0
```

## 修改後的驗證

```bash
kubectl -n taroko exec deploy/tkadm -c tkadm -- sh -c \
  'cat /etc/ssh/sshd_config.d/rdp-vscode.conf;
   /usr/sbin/sshd -T | grep -E "^(port|allowtcpforwarding|allowstreamlocalforwarding)"'
```

```
# Required by rdp-vscode (Open Remote-SSH tunnels to vscodium-server)
AllowTcpForwarding local
port 22100
allowtcpforwarding local
allowstreamlocalforwarding yes
```

- 新 pod：`tkadm-67f77d78fd-s5dxc`
- DNS search 維持 `svc.tk8s.k8s` 等五筆，沒有被改到
- spike 之前留在 tkadm 上的 `~/.vscodium-server` 已隨 pod 重啟消失

## 如何還原

```bash
# 叢集
kubectl -n taroko patch deployment tkadm --type=json -p='[
 {"op":"remove","path":"/spec/template/spec/containers/0/volumeMounts/<index>"},
 {"op":"remove","path":"/spec/template/spec/volumes/<index>"}
]'   # <index> 用 kubectl get deploy tkadm -o yaml 確認，sshd-rdp-vscode 是最後一個
kubectl -n taroko delete configmap tkadm-sshd-rdp-vscode

# 範本檔
cp -p ~/tk/wulin/wk/tkadm/tkadm-dkreg.yaml.bak ~/tk/wulin/wk/tkadm/tkadm-dkreg.yaml
```
