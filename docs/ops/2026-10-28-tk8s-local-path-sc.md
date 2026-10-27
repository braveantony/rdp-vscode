# 2026-10-28 重建 tk8s 的 `local-path` StorageClass：改成 `WaitForFirstConsumer`

## 為什麼要改

rdp-vscode 的 stateful 模式用 PVC 掛 `/home`，使用叢集預設的 SC（B2）。tk8s 的預設 SC `local-path` 原本是 `volumeBindingMode: Immediate`。

local-path 的 volume 是某一台節點上的目錄，provisioner 必須先知道節點，才能建立 volume。`Immediate` 在 PVC 一建立時就開始 provision，這時候還沒有 pod 被排程，PVC 上沒有 `volume.kubernetes.io/selected-node`，provisioner 只能失敗：

```
ProvisioningFailed (x76 over 16h)  failed to provision volume with StorageClass "local-path":
                                   configuration error, no node was specified
```

vault 的 3 個 PVC 就因此 Pending 了 8 天。改成 `WaitForFirstConsumer` 後，scheduler 會先替 pod 選好節點，並寫入 `selected-node`，provisioner 再到那台節點上建立目錄。

`volumeBindingMode` 是不可變更的欄位，只能刪掉再重建。刪除和重建 SC 不會影響已經存在的 PV 和 PVC。

## 修改前的狀態

```bash
kubectl get sc local-path -o yaml
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"storage.k8s.io/v1","kind":"StorageClass","metadata":{"annotations":{},"name":"local-path"},"provisioner":"rancher.io/local-path","reclaimPolicy":"Delete","volumeBindingMode":"Immediate"}
    storageclass.kubernetes.io/is-default-class: "true"
  creationTimestamp: "2026-10-19T09:46:22Z"
  name: local-path
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

- provisioner：`docker.io/rancher/local-path-provisioner:v0.0.36`
- `vault/data-vault-{0,1,2}`：Pending 8 天

## 執行的命令

```bash
cat > local-path-sc-new.yaml <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl delete sc local-path
kubectl create -f local-path-sc-new.yaml
```

只改了 `volumeBindingMode`。`provisioner`、`reclaimPolicy` 和 default annotation 都跟原本一樣。

## 修改後的驗證

```bash
kubectl get sc local-path -o jsonpath='{.volumeBindingMode}'   # WaitForFirstConsumer
kubectl get sc                                                 # local-path (default)
```

## 對其他服務的影響：vault

SC 重建後約 15 秒，vault 的 3 個 PVC 都變成 Bound（`data-vault-0` 的 `selected-node` 是 `tk8s-control-plane-1`），各建立了一個 10Gi 的 PV。

vault pod 因此可以啟動，但接著進入 `CrashLoopBackOff`，原因是 vault 自己的授權錯誤，跟儲存無關：

```
Error initializing core: licensing could not be initialized: invalid module: "agentic-iam"
```

這不在 rdp-vscode 的範圍內，沒有處理。

## 來源檔案

`~/tk/bin/local-path-storage.0.0.35.yaml` 裡的 SC 也是 `Immediate`，但它寫的是 `reclaimPolicy: Retain`，跟叢集上的 `Delete` 不同，provisioner 的版本也不一樣（0.0.35 和 0.0.36）。叢集上的 SC 應該不是用這個檔案建立的，所以沒有修改它。`~/tk/wulin/yaml/local-path-storage.0.0.3{1,2}.yaml` 已經是 `WaitForFirstConsumer`。

## 如何還原

```bash
kubectl delete sc local-path
kubectl create -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```
