# TVShell Portable App SDK

TVShell 可以安裝第三方的 `.tvshellapp` 套件。開發者可選擇原生「宣告 UI」或相容舊版的 WebKit runtime；套件不能攜帶或執行未簽章的原生二進位檔。

## Manifest

建立 `manifest.json`：

```json
{
  "schemaVersion": 1,
  "identifier": "dev.example.my-tv-app",
  "name": "My TV App",
  "version": "1.0.0",
  "entrypoint": "https://tv.example.dev/",
  "allowedHosts": [
    "tv.example.dev",
    "cdn.example.dev"
  ]
}
```

`entrypoint` 必須使用 HTTPS，且它的主機必須列在 `allowedHosts`。目前不接受 `*` 萬用主機；跳轉到清單外的主機會由 TVShell 在 WebKit 導航層取消。

## 建立與簽署套件

```sh
swift run TVShellAppSigner generate-key developer.ed25519
swift run TVShellAppSigner sign manifest.json developer.ed25519 MyTVApp.tvshellapp
```

請妥善備份私鑰。相同 App 的更新必須沿用原本的開發者金鑰；TVShell 會拒絕由不同金鑰簽署的更新。

## 原生宣告 UI（建議）

`schemaVersion: 2` 可讓 TVShell 用 SwiftUI 原生繪製卡片和遙控器焦點，全程不載入網站：

```json
{
  "schemaVersion": 2,
  "identifier": "dev.example.native-tv-app",
  "name": "Native TV App",
  "version": "1.0.0",
  "runtime": "declarative",
  "page": {
    "title": "我的原生 App",
    "sections": [{
      "id": "main",
      "title": "精選",
      "cards": [{
        "id": "hello",
        "title": "Hello TV",
        "subtitle": "由 TVShell 原生繪製",
        "action": { "kind": "status", "value": "動作已完成" }
      }]
    }]
  }
}
```

卡片動作目前支援 `status` 與 `openURL`。`openURL` 只允許 HTTPS，且主機必須列在 manifest 的 `allowedHosts`；整份 page 會和 manifest 一起接受 Ed25519 簽章驗證。

## 安裝與遙控器

在 TVShell 的「App 管理」按 `Menu` 選擇套件。首次安裝會顯示 SHA-256 開發者指紋，使用者明確信任後才會安裝。長按 `OK` 可移除聚焦的第三方 App。

網頁會收到標準鍵盤方向鍵、Enter、Escape、Space 與媒體鍵事件，也可使用 TVShell 的 DOM Focus、捲動及虛擬滑鼠模式。設計時應提供清楚的焦點樣式、大尺寸目標與可預測的二維方向移動。
