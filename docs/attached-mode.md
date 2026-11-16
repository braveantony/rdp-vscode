# 附屬模式

適用：`1.4` 之後的版本（尚未發布）。

## 一句話

附屬模式的 container 不提供桌面，只負責執行 VSCodium，視窗顯示在同一個 Pod 裡另一個 container 的桌面上。

## 什麼時候用

預設的**獨立模式**下，rdp-vscode 自己就是桌面：使用者用遠端桌面連進來，看到的是全螢幕的 VSCodium。

如果一個 Pod 裡已經有別的 container 提供桌面（例如 rdp-firefox 的工作區模式，開發中），再讓 rdp-vscode 啟動一套 xrdp 就重複了。這時把 rdp-vscode 設成附屬模式，整個 Pod 只需要一套 xrdp。

| | 獨立模式（預設） | 附屬模式 |
|---|---|---|
| 設定 | 不設定，或 `RDP_MODE=standalone` | `RDP_MODE=attached` |
| xrdp | 啟動，聽 3389 | 不啟動 |
| 使用者怎麼開 VSCodium | 登入就開啟 | 桌面送出請求後才開啟 |
| home 由誰建立 | 這個 container | 提供桌面的 container |
| 視窗管理、輸入法 | 這個 container 的 openbox | 桌面那邊的 |

## 怎麼運作

1. container 啟動時建立登入帳號，但不建立 home。它會等提供桌面的 container 把 `/home/<帳號>` 建好，再把自己的預設設定檔補進去，已經存在的檔案不會被覆蓋。
2. 接著啟動**啟動服務**（`/opt/rdp-vscode/launcher.pl`），在 `/run/rdp-workspace/vscode.sock` 這個 unix socket（同一台機器上的程式互相通訊用的檔案）等待請求。
3. 桌面那邊連上 socket，送出一行畫面編號，例如 `:10`。
4. Linux 核心會告訴啟動服務「連線的是哪個帳號」，請求裡不需要帳號、密碼或金鑰，也無法冒用別人。
5. 啟動服務先確認這個帳號有那個畫面的授權（`~/.Xauthority` 裡的 cookie），然後以這個帳號的身分啟動 VSCodium，回覆 `OK`。不符合時回覆 `ERR <原因>`，不啟動任何程式。

同一個桌面再送一次請求，會交給已經開著的 VSCodium，不會重開。關掉 VSCodium 只會清除它的暫存資料，桌面不受影響。

## Pod 要怎麼配

附屬模式的 container 和提供桌面的 container 必須：

- **在同一個 Pod**。同一個 Pod 共用網路，VSCodium 才連得到桌面的畫面。
- **掛載同一個 `/home`**。畫面的授權檔在使用者的 home 裡。
- **掛載同一個 `/run/rdp-workspace`**（例如一個 `emptyDir`）。socket 放在這裡。
- **用同一份帳號檔案**，順序也要一樣。帳號的 UID 依順序從 1000 開始編，兩邊必須一致。

## 環境變數

除了 `MAX_SESSIONS` 用不到之外，[README 的環境變數](../README.md#環境變數)在附屬模式一樣有效。另外多三個：

| 變數 | 預設值 | 說明 |
|---|---|---|
| `RDP_MODE` | `standalone` | `standalone` 或 `attached`；其他值會讓 container 停止，Pod log 印出 `invalid RDP_MODE` |
| `LAUNCH_SOCKET` | `/run/rdp-workspace/vscode.sock` | 啟動服務的 socket 路徑 |
| `HOME_WAIT` | `300` | 等待 home 出現的秒數上限；逾時 container 會停止，由 Kubernetes 重啟 |

## 自己送一次請求

在提供桌面的 container 裡，以登入的帳號執行（`:10` 換成自己的畫面編號，可用 `echo $DISPLAY` 查）：

```bash
perl -MIO::Socket::UNIX -e '
  $s = IO::Socket::UNIX->new(Peer => "/run/rdp-workspace/vscode.sock") or die "connect: $!\n";
  print $s ":10\n"; print scalar <$s>;'
```

印出 `OK` 之後，VSCodium 的視窗會出現在這個桌面上。

## 測試

```bash
bash test/unit/launcher.test.sh <映像檔>
bash test/image/attached.test.sh <映像檔>
```

`attached.test.sh` 用同一個映像檔在一個 podman pod 裡開兩個 container，一個當桌面（獨立模式）、一個是附屬模式，從 xrdp 登入畫面登入後送出請求，確認 VSCodium 在附屬的 container 裡執行。

## 限制

- 啟動服務只認 UID 1000 以上、有 home 的帳號。
- 視窗的切換、排列由桌面那邊負責。桌面沒有工作列時，使用者無法在多個視窗之間切換。
- 中文輸入透過 X 的輸入法協定（XIM）使用桌面那邊的輸入法；桌面沒有輸入法時，只能從用戶端貼上中文。
