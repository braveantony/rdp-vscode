# rdp-vscode 設計文件

> **以執行計畫為準。** 這組文件是給人閱讀的整理版。實際實作時，以 [`docs/superpowers/plans/2026-10-27-rdp-vscode.md`](../superpowers/plans/2026-10-27-rdp-vscode.md) 為唯一依據。兩邊內容不一致時，以執行計畫為準，並回頭修正這裡。

## 這是什麼

使用者用 **RDP**（Windows 遠端桌面）連進 Kubernetes 裡的一個 pod，畫面就是全螢幕的 **VSCodium**。它會自動透過 SSH 連到叢集裡的 `tkadm` pod（帳密 bigred/bigred），讓使用者直接在 tkadm 上寫 YAML、執行 `kubectl`，並用內建瀏覽器打開剛部署好的網站。

一句話目標：**打開遠端桌面、輸入兩次密碼，就能開始練習 Kubernetes，不需要安裝或設定任何東西。**

## 狀態

| 項目 | 狀態 |
|---|---|
| 設計討論（grilling 20 題、brainstorming 盤點 6 題） | 完成 |
| 計畫 review（Codex 7 項、Fable 5.1 補充 3 項） | 完成，已修正 |
| 實作 | 尚未開始（從 Task 0 技術驗證開始） |

## 文件導覽

| 文件 | 內容 | 適合誰看 |
|---|---|---|
| [01-decisions.md](01-decisions.md) | 所有設計決策：選了什麼、為什麼、考慮過哪些替代方案 | 想知道「為什麼這樣做」的人 |
| [02-architecture.md](02-architecture.md) | 元件、連線流程、session 生命週期、多帳號模型、repo 結構 | 要實作或除錯的人 |
| [03-deployment.md](03-deployment.md) | kustomize 結構、stateless 和 stateful、儲存、資源、環境變數、tk8s 前置作業 | 要部署的人 |
| [04-roadmap.md](04-roadmap.md) | Task 0～8 白話說明與相依關係 | 想知道進度和順序的人 |
| [05-acceptance.md](05-acceptance.md) | 10 項驗收標準，以及自動和手動驗證的分工 | 要驗收的人 |
| [06-risks.md](06-risks.md) | 安全風險、已知限制、待驗證假設、review 修正紀錄 | 所有人（上線前必讀） |

## 名詞

| 名詞 | 說明 |
|---|---|
| **rdp-vscode pod** | 本專案的 pod，裡面跑 xrdp 和 VSCodium，namespace 是 `rdp-vscode` |
| **tkadm** | 叢集內既有的管理 pod（namespace `taroko`，Alpine，sshd 在 port 22100），本專案**不修改**它 |
| **VSCodium** | 用 VS Code 原始碼 build 的開源版本（MIT），可以合法重新散佈 |
| **Open Remote-SSH** | Open VSX 上的開源 SSH 遠端開發 extension（`jeanp413.open-remote-ssh`） |
| **stateless / stateful** | 兩種部署方式：pod 重建後 home 會重置／會保留 |
| **tk8s** | 目前開發用的叢集（1 個 control-plane 加 2 個 worker，cluster domain 是 `tk8s.k8s`） |
